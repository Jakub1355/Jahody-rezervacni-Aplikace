import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var calendarSync: CalendarSyncManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Google účet") {
                    if let user = auth.user {
                        LabeledContent("Přihlášen", value: user.displayName)
                        LabeledContent("E-mail", value: user.email)
                        Button("Odhlásit se", role: .destructive) {
                            app.signOut()
                        }
                    }
                }

                Section {
                    NavigationLink {
                        CalendarPickerView()
                    } label: {
                        LabeledContent(
                            "Cílový kalendář",
                            value: calendarSync.selectedCalendar?.summary ?? "Nevybrán"
                        )
                    }
                } header: {
                    Text("Google Kalendář")
                } footer: {
                    Text("Objednávky se propisují jako události do vybraného sdíleného kalendáře.")
                }

                Section("Produkty") {
                    NavigationLink("Správa číselníku produktů") {
                        ProductsSettingsView()
                    }
                }

                Section {
                    Toggle("Mock kalendář (bez Google API)", isOn: $calendarSync.useMockCalendar)
                } header: {
                    Text("Vývoj")
                } footer: {
                    Text("Pro vývoj a testování dřív, než jsou hotové OAuth klíče. Události se nikam nezapisují, jen do konzole.")
                }

                Section {
                    LabeledContent("Verze", value: Bundle.main.versionLabel)
                }
            }
            .navigationTitle("Nastavení")
        }
    }
}

private extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
