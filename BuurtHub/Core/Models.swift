import Foundation

struct Wijk: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let naam: String
    let plaats: String
    let postcodes: [String]
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
    var bio: String
    var straat: String
    var wijkId: UUID?
    var huisregelsAkkoord: Date?

    enum CodingKeys: String, CodingKey {
        case id, bio, straat
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case wijkId = "wijk_id"
        case huisregelsAkkoord = "huisregels_akkoord"
    }

    var isComplete: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && wijkId != nil && huisregelsAkkoord != nil
    }
}

struct ProfileContact: Codable, Hashable, Sendable {
    let id: UUID
    var telefoon: String
    var telefoonZichtbaar: Bool

    enum CodingKeys: String, CodingKey {
        case id, telefoon
        case telefoonZichtbaar = "telefoon_zichtbaar"
    }
}

struct WijkMember: Codable, Hashable, Sendable {
    let wijkId: UUID
    let userId: UUID
    let rol: String

    enum CodingKeys: String, CodingKey {
        case rol
        case wijkId = "wijk_id"
        case userId = "user_id"
    }
    var isAdmin: Bool { rol == "beheerder" }
}

enum GroupKind: String, Codable, Sendable {
    case chat, weggeef, markt, ondernemers, preventie, eigen

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .weggeef: "gift"
        case .markt: "tag"
        case .ondernemers: "storefront"
        case .preventie: "checkmark.shield"
        case .eigen: "person.3"
        }
    }
}

struct BuurtGroup: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let wijkId: UUID
    let soort: GroupKind
    let naam: String
    let beschrijving: String
    let sort: Int

    enum CodingKeys: String, CodingKey {
        case id, soort, naam, beschrijving, sort
        case wijkId = "wijk_id"
    }
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    let wijkId: UUID
    let authorId: UUID
    var body: String
    var imagePaths: [String]
    var hidden: Bool
    let createdAt: Date
    var editedAt: Date?
    let groupNaam: String
    let groupSoort: GroupKind
    let authorName: String
    let authorAvatar: String?
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, hidden
        case groupId = "group_id"
        case wijkId = "wijk_id"
        case authorId = "author_id"
        case imagePaths = "image_paths"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case groupNaam = "group_naam"
        case groupSoort = "group_soort"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case likedByMe = "liked_by_me"
    }
}

struct Comment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postId: UUID
    let authorId: UUID
    let body: String
    let hidden: Bool
    let createdAt: Date
    let authorName: String
    let authorAvatar: String?

    enum CodingKeys: String, CodingKey {
        case id, body, hidden
        case postId = "post_id"
        case authorId = "author_id"
        case createdAt = "created_at"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
    }
}

struct Report: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let wijkId: UUID
    let reporterId: UUID
    let postId: UUID?
    let commentId: UUID?
    let profileId: UUID?
    let reden: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reden, status
        case wijkId = "wijk_id"
        case reporterId = "reporter_id"
        case postId = "post_id"
        case commentId = "comment_id"
        case profileId = "profile_id"
        case createdAt = "created_at"
    }
}
