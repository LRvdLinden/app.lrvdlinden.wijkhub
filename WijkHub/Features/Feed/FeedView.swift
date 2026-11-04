import SwiftUI

enum Route: Hashable {
    case profile(UUID)
    case post(UUID)
    case group(BuurtGroup)
}

/// Tijdlijn van de hele wijk, of van één groep.
struct FeedView: View {
    var fixedGroup: BuurtGroup?
    /// Toon chips om op groep te filteren (alleen op de wijk-tijdlijn).
    var showsGroupChips = false
    @State private var chosenGroup: BuurtGroup?
    private var group: BuurtGroup? { fixedGroup ?? chosenGroup }

    @Environment(AppModel.self) private var model
    @State private var posts: [Post] = []
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var failed = false
    @State private var composing = false
    @State private var openPost: Post?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if showsGroupChips && !model.feedGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(title: "All", selected: chosenGroup == nil) { chosenGroup = nil }
                            ForEach(model.feedGroups) { g in
                                Chip(title: LocalizedStringKey(g.naam), symbol: g.soort.symbol, selected: chosenGroup == g) {
                                    chosenGroup = chosenGroup == g ? nil : g
                                }
                            }
                        }
                    }
                }
                if group?.soort == .preventie {
                    EmergencyBanner()
                }
                if let group, !group.beschrijving.isEmpty, group.soort != .preventie {
                    Text(group.beschrijving)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach($posts) { $post in
                    PostRow(post: $post, showGroup: group == nil,
                            onOpen: { openPost = post },
                            onRemoved: { posts.removeAll { $0.id == post.id } })
                        .contentShape(Rectangle())
                        .onTapGesture { openPost = post }
                        .onAppear { if post.id == posts.last?.id { Task { await loadMore() } } }
                }
                if loading && !posts.isEmpty {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if posts.isEmpty {
                if loading {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView {
                        Label("Could not load messages", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your internet connection.")
                    } actions: {
                        Button("Try again") { Task { await refresh() } }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Be the first to post something for your neighbours.")
                    } actions: {
                        Button("New message") { composing = true }
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { composing = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(Text("New message"))
            }
        }
        .sheet(isPresented: $composing) {
            ComposePostView(preselected: group)
        }
        .navigationDestination(item: $openPost) { post in
            PostDetailView(postId: post.id, initial: post)
        }
        .task(id: "\(model.feedVersion)-\(group?.id.uuidString ?? "all")") { await refresh() }
    }

    private func refresh() async {
        guard let wijk = model.wijk else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            let page = try await Backend.feed(wijk: wijk.id, group: group?.id)
            posts = page
            reachedEnd = page.count < 30
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }

    private func loadMore() async {
        guard !loading, !reachedEnd, let wijk = model.wijk, let last = posts.last else { return }
        loading = true
        defer { loading = false }
        if let page = try? await Backend.feed(wijk: wijk.id, group: group?.id, before: last.createdAt) {
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.filter { !known.contains($0.id) })
            reachedEnd = page.count < 30
        }
    }
}

struct EmergencyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.red, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Emergency? Call 112 first")
                    .font(.headline)
                Text("Suspicious situation without danger: call the police on 0900-8844. Then warn your neighbours here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.red.opacity(0.25)))
    }
}
