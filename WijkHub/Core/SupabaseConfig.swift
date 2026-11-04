import Foundation

/// Supabase-project van WijkHub. De publishable key is publiek bedoeld (staat in elke app-build);
/// de beveiliging zit in de RLS-regels van de database. Zet hier NOOIT de secret/service key.
enum SupabaseConfig {
    static let url = URL(string: "https://joigkwgvnidvgmbucoqg.supabase.co")!
    static let anonKey = "sb_publishable__lghEgEAygPUQVAjsJwKhg_8M8_oYJl"

    static var isConfigured: Bool { !anonKey.hasPrefix("YOUR-") && !url.absoluteString.contains("YOUR-PROJECT") }
}

/// Links in de instellingen. Leeg = de link wordt niet getoond.
enum AppLinks {
    static let website = URL(string: "https://wijk-hub.nl")
    static let privacy = URL(string: "https://wijk-hub.nl/privacy")
    static let support = URL(string: "https://wijk-hub.nl/support")
    static let terms = URL(string: "https://wijk-hub.nl/voorwaarden")
}
