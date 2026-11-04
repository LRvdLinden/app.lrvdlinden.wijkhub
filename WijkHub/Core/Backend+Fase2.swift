import Foundation
import Supabase

extension Backend {
    // MARK: Marktplaats

    static func listings(wijk: UUID, kind: ListingKind? = nil, author: UUID? = nil, includeSold: Bool = true) async throws -> [Listing] {
        var query = client.from("listings_feed").select().eq("wijk_id", value: wijk)
        if let kind { query = query.eq("soort", value: kind.rawValue) }
        if let author { query = query.eq("author_id", value: author) }
        if !includeSold { query = query.neq("status", value: ListingStatus.verkocht.rawValue) }
        return try await query.order("created_at", ascending: false).limit(200).execute().value
    }

    static func listing(_ id: UUID) async throws -> Listing {
        try await client.from("listings_feed").select().eq("id", value: id).single().execute().value
    }

    struct ListingWrite: Encodable {
        let wijk_id: UUID
        let author_id: UUID
        let soort: String
        let titel: String
        let beschrijving: String
        let prijs_type: String
        let prijs_cent: Int?
        let categorie: String
        let image_paths: [String]

        enum CodingKeys: String, CodingKey {
            case wijk_id, author_id, soort, titel, beschrijving, prijs_type, prijs_cent, categorie, image_paths
        }

        // prijs_cent altijd meesturen, ook als null (anders blijft een oude prijs staan)
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(wijk_id, forKey: .wijk_id)
            try c.encode(author_id, forKey: .author_id)
            try c.encode(soort, forKey: .soort)
            try c.encode(titel, forKey: .titel)
            try c.encode(beschrijving, forKey: .beschrijving)
            try c.encode(prijs_type, forKey: .prijs_type)
            try c.encode(prijs_cent, forKey: .prijs_cent)
            try c.encode(categorie, forKey: .categorie)
            try c.encode(image_paths, forKey: .image_paths)
        }
    }

    static func saveListing(id: UUID?, _ write: ListingWrite) async throws {
        if let id {
            try await client.from("listings").update(write).eq("id", value: id).execute()
        } else {
            try await client.from("listings").insert(write).execute()
        }
    }

    struct ListingStatusUpdate: Encodable { let status: String }

    static func setListingStatus(_ id: UUID, _ status: ListingStatus) async throws {
        try await client.from("listings").update(ListingStatusUpdate(status: status.rawValue)).eq("id", value: id).execute()
    }

    static func deleteListing(_ id: UUID) async throws {
        try await client.from("listings").delete().eq("id", value: id).execute()
    }

    static func setListingHidden(_ id: UUID, hidden: Bool) async throws {
        try await client.from("listings").update(HiddenUpdate(hidden: hidden)).eq("id", value: id).execute()
    }

    // MARK: Hulp & diensten

    static func helpItems(wijk: UUID, kind: HelpKind? = nil, author: UUID? = nil) async throws -> [HelpItem] {
        var query = client.from("help_feed").select().eq("wijk_id", value: wijk)
        if let kind { query = query.eq("soort", value: kind.rawValue) }
        if let author { query = query.eq("author_id", value: author) }
        return try await query.order("created_at", ascending: false).limit(200).execute().value
    }

    static func helpItem(_ id: UUID) async throws -> HelpItem {
        try await client.from("help_feed").select().eq("id", value: id).single().execute().value
    }

    struct HelpWrite: Encodable {
        let wijk_id: UUID
        let author_id: UUID
        let soort: String
        let categorie: String
        let titel: String
        let beschrijving: String
    }

    static func saveHelp(id: UUID?, _ write: HelpWrite) async throws {
        if let id {
            try await client.from("help_items").update(write).eq("id", value: id).execute()
        } else {
            try await client.from("help_items").insert(write).execute()
        }
    }

    struct HelpStatusUpdate: Encodable { let status: String }

    static func setHelpOpen(_ id: UUID, open: Bool) async throws {
        try await client.from("help_items").update(HelpStatusUpdate(status: open ? "open" : "afgerond")).eq("id", value: id).execute()
    }

    static func deleteHelp(_ id: UUID) async throws {
        try await client.from("help_items").delete().eq("id", value: id).execute()
    }

    static func setHelpHidden(_ id: UUID, hidden: Bool) async throws {
        try await client.from("help_items").update(HiddenUpdate(hidden: hidden)).eq("id", value: id).execute()
    }

    // MARK: Privéberichten

    struct StartParams: Encodable {
        let other: UUID
        let listing: UUID?
        let help: UUID?
    }

    static func startConversation(with other: UUID, listing: UUID? = nil, help: UUID? = nil) async throws -> UUID {
        try await client.rpc("start_conversation", params: StartParams(other: other, listing: listing, help: help))
            .execute().value
    }

    static func conversations() async throws -> [ConversationSummary] {
        try await client.from("conversations_overview").select()
            .order("last_message_at", ascending: false).execute().value
    }

    static func messages(conversation: UUID, limit: Int = 200) async throws -> [ChatMessage] {
        let rows: [ChatMessage] = try await client.from("messages").select().eq("conversation_id", value: conversation)
            .order("created_at", ascending: false).limit(limit).execute().value
        return rows.reversed()
    }

    struct NewMessage: Encodable { let conversation_id: UUID; let sender_id: UUID; let body: String }

    static func sendMessage(conversation: UUID, sender: UUID, body: String) async throws {
        try await client.from("messages").insert(NewMessage(conversation_id: conversation, sender_id: sender, body: body)).execute()
    }

    static func markRead(_ conversation: UUID) async {
        _ = try? await client.rpc("mark_conversation_read", params: ["c": conversation]).execute()
    }
}
