import SwiftUI

/// Eén bericht in een lijst. Acties lopen via `PostActions`, zodat lijst en detail hetzelfde doen.
struct PostRow: View {
    @Binding var post: Post
    var showGroup = true
    var onOpen: (() -> Void)?
    var onRemoved: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var reportTarget: ReportTarget?
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    @State private var likeTick = 0

    private var isMine: Bool { post.authorId == model.userId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(post.body)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !post.imagePaths.isEmpty {
                PostImages(paths: post.imagePaths)
            }
            actions
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
        .overlay(alignment: .topTrailing) {
            if post.hidden {
                Text("Hidden").font(.caption2.bold()).padding(6)
                    .background(.orange.opacity(0.2), in: Capsule()).padding(10)
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target)
        }
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
        .confirmationDialog("Block \(post.authorName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
        } message: {
            Text("You will no longer see messages and comments from this neighbour.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.profile(post.authorId)) {
                Avatar(path: post.authorAvatar, name: post.authorName, size: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(post.authorName))
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName.isEmpty ? String(localized: "Neighbour") : post.authorName)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    if showGroup {
                        Label(post.groupNaam, systemImage: post.groupSoort.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        Text(verbatim: "·").foregroundStyle(.secondary)
                    }
                    Text(post.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            menu
        }
    }

    private var menu: some View {
        Menu {
            if isMine {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } else {
                Button("Report message", systemImage: "flag") {
                    reportTarget = .post(post.id, wijk: post.wijkId)
                }
                Button("Block \(post.authorName)", systemImage: "hand.raised") { confirmBlock = true }
            }
            if model.isAdmin {
                Divider()
                Button(post.hidden ? LocalizedStringKey("Show again") : LocalizedStringKey("Hide for everyone"), systemImage: post.hidden ? "eye" : "eye.slash") {
                    Task { await toggleHidden() }
                }
                if !isMine {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("More actions"))
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button { Task { await toggleLike() } } label: {
                Label {
                    Text(verbatim: post.likeCount > 0 ? "\(post.likeCount)" : "")
                } icon: {
                    Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                }
                .foregroundStyle(post.likedByMe ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: likeTick)
            .accessibilityLabel(post.likedByMe ? Text("Unlike") : Text("Like"))
            .accessibilityValue(Text(verbatim: "\(post.likeCount)"))

            Button { onOpen?() } label: {
                Label {
                    Text(verbatim: post.commentCount > 0 ? "\(post.commentCount)" : "")
                } icon: {
                    Image(systemName: "bubble.right")
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Comments"))
            .accessibilityValue(Text(verbatim: "\(post.commentCount)"))

            Spacer()
            ShareLink(item: post.body) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Share"))
        }
        .font(.subheadline)
        .frame(minHeight: 32)
    }

    // MARK: Acties

    private func toggleLike() async {
        guard let me = model.userId else { return }
        let liked = !post.likedByMe
        post.likedByMe = liked
        post.likeCount += liked ? 1 : -1
        likeTick += 1
        do {
            try await Backend.setLike(post: post.id, user: me, liked: liked)
        } catch {
            post.likedByMe.toggle()
            post.likeCount += liked ? -1 : 1
        }
    }

    private func delete() async {
        do {
            try await Backend.deletePost(post.id)
            onRemoved?()
        } catch {
            model.lastError = error.localizedDescription
        }
    }

    private func toggleHidden() async {
        do {
            try await Backend.setPostHidden(post.id, hidden: !post.hidden)
            post.hidden.toggle()
        } catch {
            model.lastError = error.localizedDescription
        }
    }

    private func block() async {
        guard let me = model.userId else { return }
        do {
            try await Backend.block(post.authorId, by: me)
            model.feedVersion += 1
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}

/// 1 foto groot, 2–4 in een raster. Tik opent de foto schermvullend.
struct PostImages: View {
    let paths: [String]
    @State private var selected: String?

    var body: some View {
        let columns = paths.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(paths, id: \.self) { path in
                Button { selected = path } label: {
                    Color.secondary.opacity(0.12)
                        .aspectRatio(paths.count == 1 ? 4 / 3 : 1, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: Backend.publicURL(path)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Photo"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fullScreenCover(item: Binding(get: { selected.map(IdentifiedPath.init) }, set: { selected = $0?.id })) { item in
            PhotoViewer(path: item.id)
        }
    }
}

private struct IdentifiedPath: Identifiable { let id: String }

private struct PhotoViewer: View {
    let path: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: Backend.publicURL(path)) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView().tint(.white) }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel(Text("Close"))
        }
    }
}
