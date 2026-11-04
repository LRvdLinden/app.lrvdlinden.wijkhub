import Foundation
import Supabase

/// Alle gesprekken met de server op één plek.
enum Backend {
    static let client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
    static var auth: AuthClient { client.auth }

    // MARK: Inloggen

    static func sendEmailCode(_ email: String) async throws {
        try await auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    static func verifyEmailCode(_ email: String, code: String) async throws {
        try await auth.verifyOTP(email: email, token: code, type: .email)
    }

    static func signInWithApple(idToken: String, nonce: String) async throws {
        try await auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    static func signOut() async throws { try await auth.signOut() }

    static func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        try? await auth.signOut(scope: .local)
    }

    // MARK: Profiel

    static func profile(_ id: UUID) async throws -> Profile {
        try await client.from("profiles").select().eq("id", value: id).single().execute().value
    }

    static func contact(_ id: UUID) async throws -> ProfileContact? {
        let rows: [ProfileContact] = try await client.from("profile_contact").select().eq("id", value: id).execute().value
        return rows.first
    }

    struct ProfileUpdate: Encodable {
        let display_name: String
        let bio: String
        let straat: String
        var avatar_path: String?
    }

    static func updateProfile(_ id: UUID, name: String, bio: String, straat: String, avatarPath: String?) async throws {
        let update = ProfileUpdate(display_name: name, bio: bio, straat: straat, avatar_path: avatarPath)
        try await client.from("profiles").update(update).eq("id", value: id).execute()
    }

    struct ContactUpdate: Encodable {
        let telefoon: String
        let telefoon_zichtbaar: Bool
    }

    static func updateContact(_ id: UUID, phone: String, visible: Bool) async throws {
        try await client.from("profile_contact")
            .update(ContactUpdate(telefoon: phone, telefoon_zichtbaar: visible))
            .eq("id", value: id).execute()
    }

    struct RulesUpdate: Encodable { let huisregels_akkoord: Date }

    static func acceptRules(_ id: UUID) async throws {
        try await client.from("profiles").update(RulesUpdate(huisregels_akkoord: .now)).eq("id", value: id).execute()
    }

    // MARK: Wijken en groepen

    static func wijken() async throws -> [Wijk] {
        try await client.from("wijken").select().order("naam").execute().value
    }

    static func joinWijk(_ id: UUID) async throws {
        try await client.rpc("join_wijk", params: ["w": id]).execute()
    }

    static func membership(wijk: UUID, user: UUID) async throws -> WijkMember? {
        let rows: [WijkMember] = try await client.from("wijk_members").select()
            .eq("wijk_id", value: wijk).eq("user_id", value: user).execute().value
        return rows.first
    }

    static func wijk(_ id: UUID) async throws -> Wijk {
        try await client.from("wijken").select().eq("id", value: id).single().execute().value
    }

    static func groups(wijk: UUID) async throws -> [BuurtGroup] {
        try await client.from("groups").select().eq("wijk_id", value: wijk).order("sort").execute().value
    }

    // MARK: Berichten

    static func feed(wijk: UUID, group: UUID? = nil, author: UUID? = nil, before: Date? = nil, limit: Int = 30) async throws -> [Post] {
        var query = client.from("posts_feed").select().eq("wijk_id", value: wijk)
        if let group { query = query.eq("group_id", value: group) }
        if let author { query = query.eq("author_id", value: author) }
        if let before { query = query.lt("created_at", value: before) }
        return try await query.order("created_at", ascending: false).limit(limit).execute().value
    }

    static func post(_ id: UUID) async throws -> Post {
        try await client.from("posts_feed").select().eq("id", value: id).single().execute().value
    }

    struct NewPost: Encodable {
        let group_id: UUID
        let wijk_id: UUID
        let author_id: UUID
        let body: String
        let image_paths: [String]
    }

    static func createPost(group: BuurtGroup, author: UUID, body: String, images: [Data]) async throws {
        var paths: [String] = []
        for data in images { paths.append(try await uploadImage(data, owner: author)) }
        let post = NewPost(group_id: group.id, wijk_id: group.wijkId, author_id: author, body: body, image_paths: paths)
        try await client.from("posts").insert(post).execute()
    }

    static func deletePost(_ id: UUID) async throws {
        try await client.from("posts").delete().eq("id", value: id).execute()
    }

    struct HiddenUpdate: Encodable { let hidden: Bool }

    static func setPostHidden(_ id: UUID, hidden: Bool) async throws {
        try await client.from("posts").update(HiddenUpdate(hidden: hidden)).eq("id", value: id).execute()
    }

    struct LikeRow: Encodable { let post_id: UUID; let user_id: UUID }

    static func setLike(post: UUID, user: UUID, liked: Bool) async throws {
        if liked {
            try await client.from("post_likes").upsert(LikeRow(post_id: post, user_id: user)).execute()
        } else {
            try await client.from("post_likes").delete().eq("post_id", value: post).eq("user_id", value: user).execute()
        }
    }

    // MARK: Reacties

    static func comments(post: UUID) async throws -> [Comment] {
        try await client.from("comments_feed").select().eq("post_id", value: post)
            .order("created_at", ascending: true).execute().value
    }

    struct NewComment: Encodable { let post_id: UUID; let author_id: UUID; let body: String }

    static func addComment(post: UUID, author: UUID, body: String) async throws {
        try await client.from("comments").insert(NewComment(post_id: post, author_id: author, body: body)).execute()
    }

    static func deleteComment(_ id: UUID) async throws {
        try await client.from("comments").delete().eq("id", value: id).execute()
    }

    // MARK: Melden en blokkeren

    struct NewReport: Encodable {
        let wijk_id: UUID
        let reporter_id: UUID
        var post_id: UUID?
        var comment_id: UUID?
        var profile_id: UUID?
        var listing_id: UUID?
        var help_id: UUID?
        let reden: String
    }

    static func report(_ report: NewReport) async throws {
        try await client.from("reports").insert(report).execute()
    }

    static func openReports(wijk: UUID) async throws -> [Report] {
        try await client.from("reports").select().eq("wijk_id", value: wijk).eq("status", value: "open")
            .order("created_at", ascending: false).execute().value
    }

    struct StatusUpdate: Encodable { let status: String }

    static func closeReport(_ id: UUID) async throws {
        try await client.from("reports").update(StatusUpdate(status: "afgehandeld")).eq("id", value: id).execute()
    }

    struct BlockRow: Encodable { let blocker_id: UUID; let blocked_id: UUID }

    static func block(_ user: UUID, by me: UUID) async throws {
        try await client.from("blocks").upsert(BlockRow(blocker_id: me, blocked_id: user)).execute()
    }

    // MARK: Foto's

    static func uploadImage(_ data: Data, owner: UUID) async throws -> String {
        let path = "\(owner.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("media").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    static func publicURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return try? client.storage.from("media").getPublicURL(path: path)
    }
}
