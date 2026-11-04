import Foundation
import SwiftUI

// MARK: - Marktplaats & weggeefhoek

enum ListingKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case markt, weggeef
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .markt ? "For sale" : "Free" }
}

enum PriceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case vast, bieden, gratis
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self { case .vast: "Fixed price"; case .bieden: "Make an offer"; case .gratis: "Free" }
    }
}

enum ListingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case beschikbaar, gereserveerd, verkocht
    var id: String { rawValue }

    func label(for kind: ListingKind) -> LocalizedStringKey {
        switch self {
        case .beschikbaar: "Available"
        case .gereserveerd: "Reserved"
        case .verkocht: kind == .weggeef ? "Given away" : "Sold"
        }
    }

    var color: Color {
        switch self { case .beschikbaar: Theme.accent; case .gereserveerd: .orange; case .verkocht: .secondary }
    }
}

enum ListingCategory: String, CaseIterable, Identifiable, Sendable {
    case huis, kinderen, kleding, elektronica, tuin, sport, boeken, overig
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .huis: "Home & furniture"
        case .kinderen: "Kids & baby"
        case .kleding: "Clothing"
        case .elektronica: "Electronics"
        case .tuin: "Garden & DIY"
        case .sport: "Sport & leisure"
        case .boeken: "Books & media"
        case .overig: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .huis: "sofa"
        case .kinderen: "teddybear"
        case .kleding: "tshirt"
        case .elektronica: "desktopcomputer"
        case .tuin: "leaf"
        case .sport: "figure.run"
        case .boeken: "book"
        case .overig: "shippingbox"
        }
    }
    init(raw: String) { self = ListingCategory(rawValue: raw) ?? .overig }
}

struct Listing: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let wijkId: UUID
    let authorId: UUID
    var soort: ListingKind
    var titel: String
    var beschrijving: String
    var prijsType: PriceType
    var prijsCent: Int?
    var categorie: String
    var imagePaths: [String]
    var status: ListingStatus
    var hidden: Bool
    let createdAt: Date
    let authorName: String
    let authorAvatar: String?

    enum CodingKeys: String, CodingKey {
        case id, soort, titel, beschrijving, categorie, status, hidden
        case wijkId = "wijk_id"
        case authorId = "author_id"
        case prijsType = "prijs_type"
        case prijsCent = "prijs_cent"
        case imagePaths = "image_paths"
        case createdAt = "created_at"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
    }

    var category: ListingCategory { ListingCategory(raw: categorie) }

    /// "€ 25", "Bieden", "Gratis"
    var priceText: String {
        switch prijsType {
        case .gratis: return String(localized: "Free")
        case .bieden:
            if let prijsCent, prijsCent > 0 {
                return String(localized: "Offer from \(Self.euro(prijsCent))")
            }
            return String(localized: "Make an offer")
        case .vast:
            return Self.euro(prijsCent ?? 0)
        }
    }

    static func euro(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        let style = Decimal.FormatStyle.Currency(code: "EUR")
            .precision(.fractionLength(cents % 100 == 0 ? 0 : 2))
        return value.formatted(style)
    }
}

// MARK: - Hulp & diensten

enum HelpKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case aanbod, vraag
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .aanbod ? "Offering" : "Looking for help" }
    var symbol: String { self == .aanbod ? "hand.raised" : "questionmark.bubble" }
}

enum HelpCategory: String, CaseIterable, Identifiable, Sendable {
    case klussen, tuin, oppas, boodschappen, vervoer, computer, dieren, gezelschap, overig
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .klussen: "Odd jobs"
        case .tuin: "Garden"
        case .oppas: "Babysitting"
        case .boodschappen: "Shopping"
        case .vervoer: "Transport"
        case .computer: "Computer & phone"
        case .dieren: "Pets"
        case .gezelschap: "Company"
        case .overig: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .klussen: "hammer"
        case .tuin: "leaf"
        case .oppas: "figure.and.child.holdinghands"
        case .boodschappen: "cart"
        case .vervoer: "car"
        case .computer: "iphone"
        case .dieren: "pawprint"
        case .gezelschap: "cup.and.saucer"
        case .overig: "ellipsis.circle"
        }
    }
    init(raw: String) { self = HelpCategory(rawValue: raw) ?? .overig }
}

struct HelpItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let wijkId: UUID
    let authorId: UUID
    var soort: HelpKind
    var categorie: String
    var titel: String
    var beschrijving: String
    var status: String
    var hidden: Bool
    let createdAt: Date
    let authorName: String
    let authorAvatar: String?

    enum CodingKeys: String, CodingKey {
        case id, soort, categorie, titel, beschrijving, status, hidden
        case wijkId = "wijk_id"
        case authorId = "author_id"
        case createdAt = "created_at"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
    }

    var category: HelpCategory { HelpCategory(raw: categorie) }
    var isOpen: Bool { status == "open" }
}

// MARK: - Privéberichten

struct ConversationSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let wijkId: UUID
    let listingId: UUID?
    let helpId: UUID?
    let lastMessageAt: Date
    let partnerId: UUID
    let partnerName: String
    let partnerAvatar: String?
    let listingTitel: String?
    let helpTitel: String?
    let lastBody: String?
    let lastSender: UUID?
    let unread: Int

    enum CodingKeys: String, CodingKey {
        case id, unread
        case wijkId = "wijk_id"
        case listingId = "listing_id"
        case helpId = "help_id"
        case lastMessageAt = "last_message_at"
        case partnerId = "partner_id"
        case partnerName = "partner_name"
        case partnerAvatar = "partner_avatar"
        case listingTitel = "listing_titel"
        case helpTitel = "help_titel"
        case lastBody = "last_body"
        case lastSender = "last_sender"
    }

    var contextTitle: String? { listingTitel ?? helpTitel }
}

struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}

/// Wat een chat nodig heeft om te openen.
struct ChatTarget: Hashable, Identifiable {
    let conversationId: UUID
    let partnerId: UUID
    let partnerName: String
    let partnerAvatar: String?
    var contextTitle: String?
    var id: UUID { conversationId }
}
