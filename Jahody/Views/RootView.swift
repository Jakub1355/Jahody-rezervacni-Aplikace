import SwiftUI

/// Vstupní brána: konfigurace → přihlášení → kontrola povoleného účtu → aplikace.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var biometricLock: BiometricLock

    var body: some View {
        Group {
            if !AppModel.firebaseAvailable {
                ConfigMissingView()
            } else if auth.isRestoring {
                ProgressView("Načítám…")
            } else if auth.user == nil {
                SignInView()
            } else if orders.accessDenied {
                AccessDeniedView()
            } else {
                MainTabView()
                    .task {
                        app.startStores()
                        await orders.loadHistory()
                        await app.calendarSync.syncPending()
                    }
            }
        }
        .overlay {
            if biometricLock.isLocked {
                LockScreenView()
            }
        }
    }
}

/// Zámková obrazovka — překryje appku, dokud se uživatel neověří Face ID / kódem.
private struct LockScreenView: View {
    @EnvironmentObject private var biometricLock: BiometricLock

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image("StrawberryLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                Text("Jahody").font(.title2.bold())
                Image(systemName: "faceid")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Button {
                    biometricLock.authenticateIfNeeded()
                } label: {
                    Text("Odemknout")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { biometricLock.authenticateIfNeeded() }
    }
}

/// Chybí GoogleService-Info.plist — projekt ještě není propojený s Firebase.
private struct ConfigMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🍓").font(.system(size: 56))
            Text("Chybí konfigurace Firebase")
                .font(.title2.bold())
            Text("Do složky Jahody přidejte soubor **GoogleService-Info.plist** z Firebase Console. Přesný postup je v souboru **SETUP.md** v repozitáři.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

/// Přihlášený účet není v kolekci `allowedUsers`.
private struct AccessDeniedView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Účet nemá přístup")
                .font(.title2.bold())
            if let email = auth.user?.email {
                Text("Účet **\(email)** není v seznamu povolených členů rodiny. Přidejte ho do kolekce `allowedUsers` ve Firestore (viz SETUP.md).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Odhlásit se") {
                app.signOut()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(32)
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel())
}
