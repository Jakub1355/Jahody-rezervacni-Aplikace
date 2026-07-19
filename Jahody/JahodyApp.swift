import SwiftUI
import GoogleSignIn

@main
struct JahodyApp: App {
    @StateObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppModel.configureFirebaseIfPossible()
        _app = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.auth)
                .environmentObject(app.orders)
                .environmentObject(app.products)
                .environmentObject(app.calendarSync)
                .environmentObject(app.biometricLock)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Odemknout Face ID (pokud je zámek) a doběhnout synchronizaci.
                        app.biometricLock.authenticateIfNeeded()
                        Task { await app.calendarSync.syncPending() }
                    case .background:
                        app.biometricLock.lockIfEnabled()
                    default:
                        break
                    }
                }
        }
    }
}
