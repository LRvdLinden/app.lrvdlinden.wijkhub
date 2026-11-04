import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack {
                FeedView()
                    .navigationTitle(model.wijk?.naam ?? "WijkHub")
                    .withRoutes()
            }
            .tabItem { Label("Neighbourhood", systemImage: "house") }

            NavigationStack {
                GroupsView()
                    .withRoutes()
            }
            .tabItem { Label("Groups", systemImage: "person.3") }

            NavigationStack {
                if let me = model.userId {
                    ProfileView(userId: me)
                        .withRoutes()
                }
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .profile(let id): ProfileView(userId: id)
            case .post(let id): PostDetailView(postId: id, initial: nil)
            case .group(let group): FeedView(group: group).navigationTitle(group.naam)
            }
        }
    }
}

struct GroupsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.groups) { group in
                    NavigationLink(value: Route.group(group)) {
                        HStack(spacing: 14) {
                            Image(systemName: group.soort.symbol)
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 48, height: 48)
                                .background(Theme.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.naam).font(.headline)
                                if !group.beschrijving.isEmpty {
                                    Text(group.beschrijving)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Events, help & services and the business directory follow in a next update.")
            }
        }
        .navigationTitle("Groups")
        .refreshable { await model.reload() }
        .overlay {
            if model.groups.isEmpty {
                ContentUnavailableView("No groups yet", systemImage: "person.3")
            }
        }
    }
}
