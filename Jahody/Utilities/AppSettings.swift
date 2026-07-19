import Foundation

/// Klíče a výchozí hodnoty uživatelských nastavení (UserDefaults).
enum AppSettingsKeys {
    /// Přednastavená zpráva zákazníkovi (upravitelná v Nastavení).
    static let readyMessage = "readyMessage"
    static let defaultReadyMessage = "Dobrý den, Vaše objednávka je připravena."

    /// Zamykat aplikaci Face ID / kódem při otevření.
    static let faceIDLock = "faceIDLock"

    /// Zvolená ikona aplikace (0 = realistická, 1 = obrys červená, 2 = obrys bílá).
    static let appIconChoice = "appIconChoice"
}
