import Foundation

/// Vul hier de gegevens van je Supabase-project in (Project Settings → API).
/// De anon key is publiek bedoeld; de beveiliging zit in de RLS-regels van de database.
enum SupabaseConfig {
    static let url = URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let anonKey = "YOUR-ANON-KEY"

    static var isConfigured: Bool { !anonKey.hasPrefix("YOUR-") && !url.absoluteString.contains("YOUR-PROJECT") }
}

/// Links in de instellingen. Leeg = de link wordt niet getoond.
enum AppLinks {
    static let website = URL(string: "https://wijk-hub.nl")
    static let privacy = URL(string: "https://wijk-hub.nl/privacy")
    static let support = URL(string: "https://wijk-hub.nl/support")
    static let terms = URL(string: "https://wijk-hub.nl/voorwaarden")
}
