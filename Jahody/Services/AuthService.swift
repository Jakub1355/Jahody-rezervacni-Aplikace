import Foundation
import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

/// Přihlášený člen rodiny.
struct FamilyUser: Equatable {
    let email: String
    let displayName: String
}

enum AuthError: LocalizedError {
    case firebaseNotConfigured
    case missingClientID
    case noPresentingViewController
    case missingIDToken
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase není nakonfigurován — chybí GoogleService-Info.plist (viz SETUP.md)."
        case .missingClientID:
            return "V konfiguraci Firebase chybí CLIENT_ID."
        case .noPresentingViewController:
            return "Nepodařilo se zobrazit přihlašovací okno."
        case .missingIDToken:
            return "Google nevrátil přihlašovací token, zkuste to znovu."
        case .notSignedIn:
            return "Nejste přihlášeni Google účtem."
        }
    }
}

/// Přihlášení Googlem přes Firebase Auth. Stejný Google účet se používá
/// i pro přístup ke Google Kalendáři (scopes níže).
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var user: FamilyUser?
    /// true, dokud probíhá obnova předchozího přihlášení při startu.
    @Published private(set) var isRestoring = true

    static let calendarScopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/calendar.readonly", // čtení seznamu kalendářů
    ]

    private var authListener: AuthStateDidChangeListenerHandle?

    func start(firebaseAvailable: Bool) {
        guard firebaseAvailable else {
            isRestoring = false
            return
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser, let email = firebaseUser.email {
                    self?.user = FamilyUser(
                        email: email.lowercased(),
                        displayName: firebaseUser.displayName ?? email
                    )
                } else {
                    self?.user = nil
                }
            }
        }
        // Obnova Google session (kvůli tokenům pro Calendar API).
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] _, _ in
            Task { @MainActor in self?.isRestoring = false }
        }
    }

    func signIn() async throws {
        guard FirebaseApp.app() != nil else { throw AuthError.firebaseNotConfigured }
        guard let clientID = FirebaseApp.app()?.options.clientID else { throw AuthError.missingClientID }
        guard let presenting = UIApplication.rootViewController else { throw AuthError.noPresentingViewController }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenting,
            hint: nil,
            additionalScopes: Self.calendarScopes
        )
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingIDToken }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await Auth.auth().signIn(with: credential)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// Čerstvý OAuth access token pro Calendar API. Když chybí scopes
    /// (např. starší přihlášení), vyžádá si je.
    func freshAccessToken() async throws -> String {
        guard let googleUser = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notSignedIn
        }
        let granted = googleUser.grantedScopes ?? []
        if !Self.calendarScopes.allSatisfy(granted.contains) {
            guard let presenting = UIApplication.rootViewController else {
                throw AuthError.noPresentingViewController
            }
            _ = try await googleUser.addScopes(Self.calendarScopes, presenting: presenting)
        }
        let refreshed = try await googleUser.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
}

extension UIApplication {
    /// Nejvrchnější view controller pro prezentaci Google Sign-In okna.
    static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
