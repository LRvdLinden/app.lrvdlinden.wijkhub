import SwiftUI

struct PostDetailView: View {
    let postId: UUID
    @State var initial: Post?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var reportTarget: ReportTarget?
    @State private var sentTick = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if initial != nil {
                    PostRow(post: Binding(get: { initial! }, set: { initial = $0 }),
                            onOpen: { inputFocused = true },
                            onRemoved: { model.feedVersion += 1; dismiss() })
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }

                Text("Comments")
                    .font(.app(.headline))
                    .padding(.top, 4)

                if comments.isEmpty {
                    Text("No comments yet.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    CommentRow(comment: comment,
                               isMine: comment.authorId == model.userId,
                               canModerate: model.isAdmin,
                               onDelete: { Task { await delete(comment) } },
                               onReport: {
                                   if let wijk = model.wijk?.id { reportTarget = .comment(comment.id, wijk: wijk) }
                               })
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle(initial?.groupNaam ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .refreshable { await load() }
        .task { await load() }
        .sensoryFeedback(.success, trigger: sentTick)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Write a comment…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line))
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.app(.headline))
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(Theme.onAccent)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func load() async {
        if let fresh = try? await Backend.post(postId) { initial = fresh }
        comments = (try? await Backend.comments(post: postId)) ?? comments
    }

    private func send() async {
        guard let me = model.userId else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await Backend.addComment(post: postId, author: me, body: text)
            draft = ""
            sentTick += 1
            await load()
        } catch {
            model.lastError = error.localizedDescription
        }
    }

    private func delete(_ comment: Comment) async {
        do {
            try await Backend.deleteComment(comment.id)
            comments.removeAll { $0.id == comment.id }
            initial?.commentCount = max(0, (initial?.commentCount ?? 1) - 1)
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let isMine: Bool
    let canModerate: Bool
    var onDelete: () -> Void
    var onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: Route.profile(comment.authorId)) {
                Avatar(path: comment.authorAvatar, name: comment.authorName, size: 32)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.authorName).font(.app(.subheadline, .semibold))
                    Text(comment.createdAt.formatted(.relative(presentation: .named)))
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
                Text(comment.body).font(.app(.subheadline)).textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contextMenu {
                if isMine || canModerate {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                }
                if !isMine {
                    Button("Report comment", systemImage: "flag", action: onReport)
                }
            }
        }
    }
}
