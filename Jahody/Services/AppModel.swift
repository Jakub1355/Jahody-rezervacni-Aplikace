import Foundation
import SwiftUI
import FirebaseCore
import FirebaseFirestore

/// Kompozice služeb aplikace — vzniká jednou v `JahodyApp` a předává se
/// přes environment.
@MainActor
final class AppModel: ObservableObject {
    static private(set) var firebaseAvailable = false

    let auth: AuthService
    let orders: OrderStore
    let products: ProductStore
    let calendarSync: CalendarSyncManager
    let biometricLock = BiometricLock()

    /// Nakonfiguruje Firebase, pokud je v projektu GoogleService-Info.plist.
    /// Bez něj aplikace ukáže obrazovku s odkazem na SETUP.md.
    static func configureFirebaseIfPossible() {
        guard !firebaseAvailable else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("⚠️ Chybí GoogleService-Info.plist — Firebase nenakonfigurován, viz SETUP.md.")
            return
        }
        FirebaseApp.configure()

        // Offline persistence — na farmě není vždy signál; zápisy musí projít
        // offline a synchronizovat se později.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        firebaseAvailable = true
    }

    init() {
        Self.configureFirebaseIfPossible()

        let auth = AuthService()
        let orders = OrderStore()
        self.auth = auth
        self.orders = orders
        self.products = ProductStore()
        self.calendarSync = CalendarSyncManager(
            realService: GoogleCalendarService(tokenProvider: { try await auth.freshAccessToken() }),
            orders: orders,
            auth: auth
        )

        auth.start(firebaseAvailable: Self.firebaseAvailable)
    }

    /// Spustí listenery po ověření přístupu (přihlášený povolený účet).
    func startStores() {
        orders.start()
        products.start()
    }

    func signOut() {
        orders.stop()
        products.stop()
        auth.signOut()
    }
}
