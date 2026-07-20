import UIKit

/// Volby vzhledu ikony aplikace (a shodné jahody na přihlašovací obrazovce).
enum AppIconOption: Int, CaseIterable, Identifiable {
    case realistic = 0
    case redOnWhite = 1
    case whiteOnRed = 2

    var id: Int { rawValue }

    /// Obrázek v Assets pro přihlašovací a zámkovou obrazovku.
    var loginAsset: String {
        switch self {
        case .realistic: return "StrawberryLogo"
        case .redOnWhite: return "StrawberryLogo2"
        case .whiteOnRed: return "StrawberryLogo3"
        }
    }

    /// Název alternativní ikony v Info.plist (nil = původní/primární ikona).
    var alternateIconName: String? {
        switch self {
        case .realistic: return nil
        case .redOnWhite: return "AppIcon2"
        case .whiteOnRed: return "AppIcon3"
        }
    }

    var label: String {
        switch self {
        case .realistic: return "Jahoda (barevná)"
        case .redOnWhite: return "Obrys – červená na bílé"
        case .whiteOnRed: return "Obrys – bílá na červené"
        }
    }
}

/// Přepínání ikony na ploše (iOS alternativní ikony).
enum AppIconManager {
    static var current: AppIconOption {
        let raw = UserDefaults.standard.integer(forKey: AppSettingsKeys.appIconChoice)
        return AppIconOption(rawValue: raw) ?? .realistic
    }

    /// Nastaví ikonu na ploše podle volby. iOS při změně ukáže systémové okno.
    static func apply(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let name = option.alternateIconName
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}
