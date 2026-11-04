import SwiftUI

/// Tabblad Hulp: buren bieden hulp of diensten aan, of vragen erom.
struct HelpView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [HelpItem] = []
    @State private var filter: Filter = .all
    @State private var category: HelpCategory?
    @State private var showClosed = false
    @State private var search = ""
    @State private var loading = false
    @State private var failed = false
    @State private var creating: HelpKind?

    enum Filter: String, CaseIterable, Identifiable {
        case all, vraag, aanbod, mine
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .all: "All"; case .vraag: "Requests"; case .aanbod: "Offers"; case .mine: "Mine" }
        }
    }

    private var visible: [HelpItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { i in
            switch filter {
            case .all: true
            case .vraag: i.soort == .vraag
            case .aanbod: i.soort == .aanbod
            case .mine: i.authorId == model.userId
            }
        }
        .filter { showClosed || filter == .mine || $0.isOpen }
        .filter { category == nil || $0.category == category }
        .filter { q.isEmpty || $0.titel.lowercased().contains(q) || $0.beschrijving.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    BigAction(title: "Ask for help", symbol: "questionmark.bubble") { creating = .vraag }
                    BigAction(title: "Offer help", symbol: "hand.raised") { creating = .aanbod }
                }

                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "All categories", symbol: "square.grid.2x2", selected: category == nil) { category = nil }
                        ForEach(HelpCategory.allCases) { c in
                            Chip(title: c.label, symbol: c.symbol, selected: category == c) { category = category == c ? nil : c }
                        }
                    }
                }

                LazyVStack(spacing: 10) {
                    ForEach(visible) { item in
                        NavigationLink(value: item) { HelpRow(item: item) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .searchable(text: $search, prompt: Text("Search help & services"))
        .overlay {
            if visible.isEmpty {
                if loading && items.isEmpty {
                    ProgressView()
                } else if failed && items.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load help & services", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ContentUnavailableView("Nothing here yet", systemImage: "hand.raised",
                                           description: Text("Need a hand, or happy to help? Post it here."))
                        .padding(.top, 160)
                }
            }
        }
        .navigationTitle("Help & services")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show completed", isOn: $showClosed)
            }
        }
        .sheet(item: $creating) { HelpEditor(existing: nil, kind: $0) }
        .refreshable { await load() }
        .task(id: model.feedVersion) { await load() }
    }

    private func load() async {
        guard let wijk = model.wijk?.id else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            items = try await Backend.helpItems(wijk: wijk)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

private struct BigAction: View {
    let title: LocalizedStringKey
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.app(.title2))
                Text(title).font(.app(.subheadline, .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}

struct HelpRow: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.symbol)
                .font(.app(.title3))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.soort.label)
                        .font(.app(.caption, .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(item.soort == .vraag ? Color.orange.opacity(0.18) : Theme.tint, in: Capsule())
                        .foregroundStyle(item.soort == .vraag ? Color.orange : Theme.accent)
                    if !item.isOpen {
                        Text("Completed").font(.app(.caption, .bold)).foregroundStyle(.secondary)
                    }
                }
                Text(item.titel).font(.app(.headline)).lineLimit(2)
                if !item.beschrijving.isEmpty {
                    Text(item.beschrijving).font(.app(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(verbatim: "\(item.authorName) · \(item.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
        .opacity(item.isOpen ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

struct HelpDetailView: View {
    @State var item: HelpItem

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var reportTarget: ReportTarget?
    @State private var confirmDelete = false
    @State private var chat: ChatTarget?
    @State private var starting = false
    @State private var doneTick = 0

    private var isMine: Bool { item.authorId == model.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HelpRow(item: item)
                if !item.beschrijving.isEmpty {
                    Text(item.beschrijving).textSelection(.enabled)
                }
                NavigationLink(value: Route.profile(item.authorId)) {
                    HStack(spacing: 12) {
                        Avatar(path: item.authorAvatar, name: item.authorName, size: 44)
                        Text(item.authorName).font(.app(.headline))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                if isMine {
                    Button {
                        Task { await toggleDone() }
                    } label: {
                        Text(item.isOpen ? LocalizedStringKey("Mark as completed") : LocalizedStringKey("Open again"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if item.isOpen {
                    Button { Task { await startChat() } } label: {
                        ProgressLabel(title: item.soort == .vraag ? "I can help" : "Send a message", busy: starting)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(starting)
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(item.soort.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isMine {
                        Button("Edit", systemImage: "pencil") { editing = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } else {
                        Button("Report", systemImage: "flag") { reportTarget = .help(item.id, wijk: item.wijkId) }
                        if model.isAdmin {
                            Button(item.hidden ? LocalizedStringKey("Show again") : LocalizedStringKey("Hide for everyone"),
                                   systemImage: item.hidden ? "eye" : "eye.slash") { Task { await toggleHidden() } }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("More actions"))
            }
        }
        .sheet(isPresented: $editing, onDismiss: { Task { await reload() } }) { HelpEditor(existing: item, kind: item.soort) }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
        .navigationDestination(item: $chat) { ChatView(target: $0) }
        .sensoryFeedback(.success, trigger: doneTick)
    }

    private func reload() async {
        if let fresh = try? await Backend.helpItem(item.id) { item = fresh }
    }

    private func toggleDone() async {
        do {
            try await Backend.setHelpOpen(item.id, open: !item.isOpen)
            item.status = item.isOpen ? "afgerond" : "open"
            doneTick += 1
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func toggleHidden() async {
        do {
            try await Backend.setHelpHidden(item.id, hidden: !item.hidden)
            item.hidden.toggle()
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func delete() async {
        do {
            try await Backend.deleteHelp(item.id)
            model.feedVersion += 1
            dismiss()
        } catch { model.lastError = error.localizedDescription }
    }

    private func startChat() async {
        starting = true
        defer { starting = false }
        do {
            let id = try await Backend.startConversation(with: item.authorId, help: item.id)
            chat = ChatTarget(conversationId: id, partnerId: item.authorId, partnerName: item.authorName,
                              partnerAvatar: item.authorAvatar, contextTitle: item.titel)
        } catch {
            model.lastError = String(localized: "Could not start a conversation.")
        }
    }
}

struct HelpEditor: View {
    let existing: HelpItem?
    @State var kind: HelpKind

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var titel = ""
    @State private var beschrijving = ""
    @State private var category: HelpCategory = .overig
    @State private var busy = false
    @State private var error: String?
    @State private var saved = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Looking for help").tag(HelpKind.vraag)
                        Text("Offering").tag(HelpKind.aanbod)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField(kind == .vraag ? LocalizedStringKey("What do you need help with?") : LocalizedStringKey("What can you offer?"),
                              text: $titel)
                    TextField("More details: when, how long, any costs", text: $beschrijving, axis: .vertical)
                        .lineLimit(3...10)
                    Picker("Category", selection: $category) {
                        ForEach(HelpCategory.allCases) { c in Label(c.label, systemImage: c.symbol).tag(c) }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.app(.footnote)) }
                }
            }
            .navigationTitle(kind == .vraag ? LocalizedStringKey("Ask for help") : LocalizedStringKey("Offer help"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button(existing == nil ? LocalizedStringKey("Post") : LocalizedStringKey("Save")) { Task { await save() } }
                            .disabled(titel.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .onAppear {
            if let e = existing {
                titel = e.titel; beschrijving = e.beschrijving; category = e.category
            }
        }
    }

    private func save() async {
        guard let me = model.userId, let wijk = model.wijk?.id else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let write = Backend.HelpWrite(wijk_id: existing?.wijkId ?? wijk, author_id: existing?.authorId ?? me,
                                          soort: kind.rawValue, categorie: category.rawValue,
                                          titel: titel.trimmingCharacters(in: .whitespaces),
                                          beschrijving: beschrijving.trimmingCharacters(in: .whitespacesAndNewlines))
            try await Backend.saveHelp(id: existing?.id, write)
            saved += 1
            model.feedVersion += 1
            dismiss()
        } catch {
            self.error = String(localized: "Your post could not be saved. Try again.")
        }
    }
}
