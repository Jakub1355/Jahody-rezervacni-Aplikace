import Foundation
import LocalAuthentication

/// Zámek aplikace přes Face ID / Touch ID (nebo kód telefonu).
/// Přihlášení Googlem zůstává; tohle jen chrání otevřenou aplikaci.
@MainActor
final class BiometricLock: ObservableObject {
    /// Je aplikace teď zamčená (má se překrýt zámkovou obrazovkou)?
    @Published private(set) var isLocked: Bool

    init() {
        // Při startu zamknout, pokud je zámek v nastavení zapnutý.
        isLocked = UserDefaults.standard.bool(forKey: AppSettingsKeys.faceIDLock)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKeys.faceIDLock)
    }

    /// Zamkne při odchodu do pozadí (pokud je zámek zapnutý).
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    /// Když je zamčeno, vyžádá Face ID / kód; při úspěchu odemkne.
    func authenticateIfNeeded() {
        guard isLocked else { return }
        let context = LAContext()
        context.localizedFallbackTitle = "Zadat kód"

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication // biometrie, jinak kód
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // Zařízení neumí ověřit (žádná biometrie ani kód) → nezablokovat přístup.
            isLocked = false
            return
        }

        context.evaluatePolicy(policy, localizedReason: "Odemkněte aplikaci Jahody") { success, _ in
            Task { @MainActor in
                if success { self.isLocked = false }
            }
        }
    }

    /// Reakce na změnu přepínače v Nastavení: vypnutí hned odemkne.
    /// (Zapnutí se projeví až při dalším otevření aplikace.)
    func settingChanged() {
        if !isEnabled { isLocked = false }
    }
}
