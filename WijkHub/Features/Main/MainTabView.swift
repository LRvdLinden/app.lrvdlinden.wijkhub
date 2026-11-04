import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                FeedView(showsGroupChips: true)
                    .navigationTitle(model.wijk?.naam ?? "WijkHub")
                    .withRoutes()
            }
            .tabItem { Label("Neighbourhood", systemImage: "house") }

            NavigationStack {
                MarketView().withRoutes()
            }
            .tabItem { Label("Market", systemImage: "tag") }

            NavigationStack {
                HelpView().withRoutes()
            }
            .tabItem { Label("Help", systemImage: "hand.raised") }

            NavigationStack {
                ConversationsView().withRoutes()
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.text.bubble.right") }
            .badge(model.unreadMessages)

            NavigationStack {
                if let me = model.userId {
                    ProfileView(userId: me).withRoutes()
                }
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task { await model.refreshUnread() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshUnread() } }
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
        self
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile(let id): ProfileView(userId: id)
                case .post(let id): PostDetailView(postId: id, initial: nil)
                case .group(let group): FeedView(fixedGroup: group).navigationTitle(group.naam)
                }
            }
            .navigationDestination(for: Listing.self) { ListingDetailView(listing: $0) }
            .navigationDestination(for: HelpItem.self) { HelpDetailView(item: $0) }
            .navigationDestination(for: ChatTarget.self) { ChatView(target: $0) }
    }
}
