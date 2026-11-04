import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        let (lr, lg, lb) = rgb(light), (dr, dg, db) = rgb(dark)
        #if os(watchOS)
        _ = (lr, lg, lb)
        self.init(red: dr, green: dg, blue: db)
        #elseif canImport(UIKit)
        self.init(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
            : UIColor(red: lr, green: lg, blue: lb, alpha: 1) })
        #else
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: dr, green: dg, blue: db, alpha: 1)
                : NSColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
        #endif
    }
}

/// BuurtHub-huisstijl, afgeleid van Samen Zuidbroek (#0B7D36, #8EC152, wit).
/// Lichtgroen is te licht voor tekst op wit: alleen voor accenten gebruiken.
enum Theme {
    static let green = Color(red: 0x0B / 255, green: 0x7D / 255, blue: 0x36 / 255)
    static let lime = Color(red: 0x8E / 255, green: 0xC1 / 255, blue: 0x52 / 255)
    /// Knoppen, links en accenttekst: donkergroen in licht, lichtgroen in donker.
    static let accent = Color(light: 0x0B7D36, dark: 0x8EC152)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0E2414)
    static let tint = Color(light: 0xE7F3DC, dark: 0x1B3322)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1F1B)
    static let background = Color(light: 0xF6F7F3, dark: 0x0F1210)
    static let line = Color(light: 0xE4E8DF, dark: 0x2A322C)
    static let ink = Color(light: 0x17301F, dark: 0xE8EEE8)
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self { case .system: "Automatic"; case .light: "Light"; case .dark: "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// Taal van de app, voor teksten met een eigen tabel (MoreAppsText, AppInfoText).
enum AppLanguage {
    static var code: String {
        let lang = String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2))
        return lang == "nb" ? "no" : lang
    }
}
