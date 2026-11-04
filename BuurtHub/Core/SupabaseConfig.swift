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
    static let privacy: URL? = nil
    static let support: URL? = nil
    static let terms: URL? = nil
}
