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
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Návrat do popředí → doběhnout odloženou synchronizaci kalendáře.
                    if phase == .active {
                        Task { await app.calendarSync.syncPending() }
                    }
                }
        }
    }
}
