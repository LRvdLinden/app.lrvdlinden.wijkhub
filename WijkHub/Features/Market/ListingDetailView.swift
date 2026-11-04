import SwiftUI

struct ListingDetailView: View {
    @State var listing: Listing

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var reportTarget: ReportTarget?
    @State private var confirmDelete = false
    @State private var chat: ChatTarget?
    @State private var starting = false
    @State private var statusTick = 0

    private var isMine: Bool { listing.authorId == model.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photos

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(listing.soort.label, systemImage: listing.soort == .markt ? "tag" : "gift")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        if listing.status != .beschikbaar {
                            StatusBadge(status: listing.status, kind: listing.soort)
                        }
                    }
                    Text(listing.titel).font(.title2.bold())
                    Text(listing.priceText).font(.title3.weight(.bold)).foregroundStyle(Theme.accent)
                    HStack(spacing: 6) {
                        Label(listing.category.label, systemImage: listing.category.symbol)
                        Text(verbatim: "·")
                        Text(listing.createdAt.formatted(.relative(presentation: .named)))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if !listing.beschrijving.isEmpty {
                    Text(listing.beschrijving).textSelection(.enabled)
                }

                NavigationLink(value: Route.profile(listing.authorId)) {
                    HStack(spacing: 12) {
                        Avatar(path: listing.authorAvatar, name: listing.authorName, size: 44)
                        VStack(alignment: .leading) {
                            Text(listing.authorName).font(.headline)
                            Text(model.wijk?.naam ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)

                if isMine {
                    ownerActions
                } else if listing.status != .verkocht {
                    Button { Task { await startChat() } } label: {
                        ProgressLabel(title: listing.soort == .weggeef ? "I'm interested" : "Send a message", busy: starting)
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
        .navigationTitle(listing.titel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { menu }
        }
        .sheet(isPresented: $editing, onDismiss: { Task { await reload() } }) { ListingEditor(existing: listing) }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .confirmationDialog("Delete this ad?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
        .navigationDestination(item: $chat) { ChatView(target: $0) }
        .sensoryFeedback(.success, trigger: statusTick)
        .refreshable { await reload() }
    }

    @ViewBuilder private var photos: some View {
        if listing.imagePaths.isEmpty {
            EmptyView()
        } else {
            TabView {
                ForEach(listing.imagePaths, id: \.self) { path in
                    AsyncImage(url: Backend.publicURL(path)) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: listing.imagePaths.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 320)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var ownerActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status").font(.headline)
            Picker("Status", selection: Binding(get: { listing.status }, set: { new in Task { await setStatus(new) } })) {
                ForEach(ListingStatus.allCases) { Text($0.label(for: listing.soort)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Neighbours can see the status. Sold and given-away items are hidden in the market unless someone chooses to show them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var menu: some View {
        Menu {
            ShareLink(item: "\(listing.titel) – \(listing.priceText)")
            if isMine {
                Button("Edit", systemImage: "pencil") { editing = true }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } else {
                Button("Report ad", systemImage: "flag") {
                    reportTarget = .listing(listing.id, wijk: listing.wijkId)
                }
            }
            if model.isAdmin && !isMine {
                Button(listing.hidden ? LocalizedStringKey("Show again") : LocalizedStringKey("Hide for everyone"),
                       systemImage: listing.hidden ? "eye" : "eye.slash") {
                    Task { await toggleHidden() }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("More actions"))
    }

    private func reload() async {
        if let fresh = try? await Backend.listing(listing.id) { listing = fresh }
    }

    private func setStatus(_ status: ListingStatus) async {
        let old = listing.status
        listing.status = status
        do {
            try await Backend.setListingStatus(listing.id, status)
            statusTick += 1
            model.feedVersion += 1
        } catch {
            listing.status = old
            model.lastError = error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await Backend.deleteListing(listing.id)
            model.feedVersion += 1
            dismiss()
        } catch { model.lastError = error.localizedDescription }
    }

    private func toggleHidden() async {
        do {
            try await Backend.setListingHidden(listing.id, hidden: !listing.hidden)
            listing.hidden.toggle()
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func startChat() async {
        starting = true
        defer { starting = false }
        do {
            let id = try await Backend.startConversation(with: listing.authorId, listing: listing.id)
            chat = ChatTarget(conversationId: id, partnerId: listing.authorId, partnerName: listing.authorName,
                              partnerAvatar: listing.authorAvatar, contextTitle: listing.titel)
        } catch {
            model.lastError = String(localized: "Could not start a conversation.")
        }
    }
}
