import SwiftUI
import UIKit

/// Huisletters van Samen Zuidbroek: Poppins voor tekst, Social Gothic voor koppen en het woordmerk.
/// Ontbreekt een font (bv. Social Gothic niet meegeleverd), dan valt alles terug op Poppins of de systeemletter.
enum BrandFont {
    static let socialGothicBold = "SocialGothic-Bold"
    static let socialGothicDemi = "SocialGothic-DemiBold"

    static func poppins(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: "Poppins-Light"
        case .medium: "Poppins-Medium"
        case .semibold: "Poppins-SemiBold"
        case .bold: "Poppins-Bold"
        case .heavy, .black: "Poppins-ExtraBold"
        default: "Poppins-Regular"
        }
    }

    static func isAvailable(_ name: String) -> Bool { UIFont(name: name, size: 12) != nil }

    /// Standaardgroottes van iOS; Poppins valt wat groter uit, daarom iets kleiner.
    static func size(for style: Font.TextStyle) -> CGFloat {
        let base: CGFloat = switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
        return (base * 0.94).rounded()
    }

    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}

extension Font {
    /// Poppins in een iOS-tekststijl, schaalt mee met Dynamische tekst.
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let w = weight ?? BrandFont.defaultWeight(for: style)
        let name = BrandFont.poppins(w)
        guard BrandFont.isAvailable(name) else { return .system(style).weight(w) }
        return .custom(name, size: BrandFont.size(for: style), relativeTo: style)
    }

    /// Social Gothic voor koppen; valt terug op Poppins Bold.
    static func display(_ style: Font.TextStyle, demi: Bool = false) -> Font {
        let name = demi ? BrandFont.socialGothicDemi : BrandFont.socialGothicBold
        guard BrandFont.isAvailable(name) else { return .app(style, .bold) }
        return .custom(name, size: BrandFont.size(for: style) * 1.12, relativeTo: style)
    }

    /// Vaste grootte (woordmerk, splash).
    static func display(size: CGFloat) -> Font {
        if BrandFont.isAvailable(BrandFont.socialGothicBold) { return .custom(BrandFont.socialGothicBold, fixedSize: size) }
        if BrandFont.isAvailable("Poppins-ExtraBold") { return .custom("Poppins-ExtraBold", fixedSize: size) }
        return .system(size: size, weight: .heavy, design: .rounded)
    }
}

enum BrandAppearance {
    /// Navigatiebalk en tabbalk in de huisletters (UIKit-onderdelen die SwiftUI niet zelf stijlt).
    static func apply() {
        func metrics(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont? {
            guard let f = UIFont(name: name, size: size) else { return nil }
            return UIFontMetrics(forTextStyle: style).scaledFont(for: f)
        }
        let nav = UINavigationBar.appearance()
        if let large = metrics(BrandFont.socialGothicBold, 36, .largeTitle) ?? metrics("Poppins-Bold", 32, .largeTitle) {
            nav.largeTitleTextAttributes = [.font: large]
        }
        if let title = metrics("Poppins-SemiBold", 17, .headline) {
            nav.titleTextAttributes = [.font: title]
        }
        if let tab = UIFont(name: "Poppins-Medium", size: 10) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
        }
        if let button = metrics("Poppins-Regular", 17, .body) {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: button], for: .normal)
        }
    }
}
