import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @AppStorage("ui.appearance") private var appearance: AppearanceSetting = .system
    @State private var showWhatsNew = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        List {
            // 1. App-specifiek
            Section("Account") {
                if let email = model.email {
                    LabeledContent("E-mail address", value: email)
                }
                if let wijk = model.wijk {
                    LabeledContent("Neighbourhood", value: "\(wijk.naam), \(wijk.plaats)")
                }
                if AppLock.biometryAvailable {
                    Toggle("Lock with Face ID", isOn: Binding(
                        get: { lock.isEnabled },
                        set: { on in
                            if on { Task { _ = await lock.enable() } } else { lock.isEnabled = false }
                        }))
                    .tint(Theme.accent)
                }
            }

            if model.isAdmin {
                Section("Administration") {
                    NavigationLink {
                        ReportsAdminView()
                    } label: {
                        Label("Reports", systemImage: "flag")
                    }
                }
            }

            // 2. Weergave
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // 3. Links
            Section {
                if let privacy = AppLinks.privacy {
                    Link(destination: privacy) { Label("Privacy statement", systemImage: "hand.raised") }
                }
                if let terms = AppLinks.terms {
                    Link(destination: terms) { Label("Terms of use", systemImage: "doc.text") }
                }
                if let support = AppLinks.support {
                    Link(destination: support) { Label("Support & contact", systemImage: "questionmark.circle") }
                }
                Button { showWhatsNew = true } label: {
                    Label("What's new", systemImage: "sparkles")
                }
            }

            Section {
                Button("Log out") { confirmSignOut = true }
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .disabled(deleting)
            } footer: {
                Text("Deleting your account permanently removes your profile, messages, comments and photos.")
            }

            // 4. Ontdekken
            Section(MoreAppsText.current.section) {
                MoreAppsCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // 5. App-info
            Section {
                AppInfoFooter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
        .confirmationDialog("Log out of WijkHub?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { Task { await model.signOut() } }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do { try await model.deleteAccount() } catch { model.lastError = error.localizedDescription }
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        BrandLogo(markSize: 36)
                        Text(verbatim: "1.0.0").font(.app(.subheadline)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Label("Your neighbourhood's chat, give-away corner, marketplace, business corner and neighbourhood watch in one app", systemImage: "house")
                    Label("Post messages with photos, react and like", systemImage: "bubble.left.and.bubble.right")
                    Label("Profiles with an optional phone number", systemImage: "person.crop.circle")
                    Label("Report and block, so the neighbourhood stays pleasant", systemImage: "flag")
                    Label("Lock the app with Face ID", systemImage: "faceid")
                }
                Section {
                    Label("Market: sell or give away, and mark items as reserved or sold", systemImage: "tag")
                    Label("Help & services: ask for help or offer it", systemImage: "hand.raised")
                    Label("Private messages with your neighbours", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Voor beheerders: open meldingen bekijken, bericht verbergen en afhandelen.
struct ReportsAdminView: View {
    @Environment(AppModel.self) private var model
    @State private var reports: [Report] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(kind(report), systemImage: symbol(report))
                            .font(.app(.subheadline, .semibold))
                        Spacer()
                        Text(report.createdAt.formatted(.relative(presentation: .named)))
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Text(report.reden).font(.app(.body))
                    HStack {
                        if let postId = report.postId {
                            NavigationLink("View message") { PostDetailView(postId: postId, initial: nil).withRoutes() }
                                .font(.app(.subheadline))
                            Spacer()
                            Button("Hide message") { Task { await hide(postId, report: report) } }
                                .buttonStyle(.bordered)
                        } else if let listingId = report.listingId {
                            Button("Hide ad") { Task { await hideListing(listingId, report: report) } }
                                .buttonStyle(.bordered)
                            Spacer()
                        } else if let helpId = report.helpId {
                            Button("Hide post") { Task { await hideHelp(helpId, report: report) } }
                                .buttonStyle(.bordered)
                            Spacer()
                        } else if let profileId = report.profileId {
                            NavigationLink("View profile") { ProfileView(userId: profileId).withRoutes() }
                                .font(.app(.subheadline))
                            Spacer()
                        } else {
                            Spacer()
                        }
                        Button("Resolved") { Task { await close(report) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Reports")
        .overlay {
            if loading && reports.isEmpty {
                ProgressView()
            } else if reports.isEmpty {
                ContentUnavailableView("No open reports", systemImage: "checkmark.seal")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func kind(_ report: Report) -> LocalizedStringKey {
        if report.postId != nil { return "Message" }
        if report.commentId != nil { return "Comment" }
        if report.listingId != nil { return "Ad" }
        if report.helpId != nil { return "Help & services" }
        return "Profile"
    }

    private func symbol(_ report: Report) -> String {
        if report.postId != nil { return "text.bubble" }
        if report.commentId != nil { return "bubble.right" }
        if report.listingId != nil { return "tag" }
        if report.helpId != nil { return "hand.raised" }
        return "person"
    }

    private func hideListing(_ id: UUID, report: Report) async {
        do {
            try await Backend.setListingHidden(id, hidden: true)
            try await Backend.closeReport(report.id)
            reports.removeAll { $0.id == report.id }
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func hideHelp(_ id: UUID, report: Report) async {
        do {
            try await Backend.setHelpHidden(id, hidden: true)
            try await Backend.closeReport(report.id)
            reports.removeAll { $0.id == report.id }
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func load() async {
        guard let wijk = model.wijk?.id else { return }
        loading = true
        defer { loading = false }
        reports = (try? await Backend.openReports(wijk: wijk)) ?? reports
    }

    private func hide(_ postId: UUID, report: Report) async {
        do {
            try await Backend.setPostHidden(postId, hidden: true)
            try await Backend.closeReport(report.id)
            reports.removeAll { $0.id == report.id }
            model.feedVersion += 1
        } catch { model.lastError = error.localizedDescription }
    }

    private func close(_ report: Report) async {
        do {
            try await Backend.closeReport(report.id)
            reports.removeAll { $0.id == report.id }
        } catch { model.lastError = error.localizedDescription }
    }
}
