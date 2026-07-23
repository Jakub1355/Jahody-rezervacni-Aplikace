import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var calendarSync: CalendarSyncManager

    @EnvironmentObject private var biometricLock: BiometricLock
    @EnvironmentObject private var products: ProductStore
    @AppStorage(AppSettingsKeys.readyMessage) private var readyMessage = AppSettingsKeys.defaultReadyMessage
    @AppStorage(AppSettingsKeys.faceIDLock) private var faceIDLock = false
    @AppStorage(AppSettingsKeys.appIconChoice) private var iconChoice = 0
    @State private var showsLoadPriceList = false

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

                Section {
                    NavigationLink("Správa číselníku produktů") {
                        ProductsSettingsView()
                    }
                    Button("Načíst náš ceník") {
                        showsLoadPriceList = true
                    }
                } header: {
                    Text("Produkty")
                } footer: {
                    Text("„Načíst náš ceník" nahraje kompletní ceník farmy (jahody, sirupy, jogurty…) a smaže dosavadní testovací produkty.")
                }

                Section {
                    TextField("Zpráva zákazníkovi", text: $readyMessage, axis: .vertical)
                        .lineLimit(2...5)
                    if readyMessage != AppSettingsKeys.defaultReadyMessage {
                        Button("Obnovit výchozí text") {
                            readyMessage = AppSettingsKeys.defaultReadyMessage
                        }
                        .font(.callout)
                    }
                } header: {
                    Text("Zpráva zákazníkovi")
                } footer: {
                    Text("Přednastavený text pro SMS / WhatsApp / Messenger, když dáváte vědět, že je objednávka připravená. Použije se z detailu objednávky.")
                }

                Section {
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        LabeledContent(
                            "Ikona aplikace",
                            value: (AppIconOption(rawValue: iconChoice) ?? .realistic).label
                        )
                    }
                } footer: {
                    Text("Změní ikonu na ploše i jahodu na přihlašovací obrazovce.")
                }

                Section {
                    Toggle("Zamykat aplikaci Face ID", isOn: $faceIDLock)
                        .onChange(of: faceIDLock) { _, _ in
                            biometricLock.settingChanged()
                        }
                } header: {
                    Text("Zabezpečení")
                } footer: {
                    Text("Po zapnutí bude aplikace při každém otevření vyžadovat Face ID (nebo kód telefonu). Přihlášení Googlem zůstává.")
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
            .confirmationDialog(
                "Načíst náš ceník?",
                isPresented: $showsLoadPriceList,
                titleVisibility: .visible
            ) {
                Button("Načíst a nahradit", role: .destructive) {
                    products.loadPriceList()
                }
                Button("Zpět", role: .cancel) {}
            } message: {
                Text("Nahraje kompletní ceník farmy a smaže dosavadní testovací produkty. Staré objednávky zůstanou nedotčené.")
            }
        }
    }
}

/// Výběr ikony aplikace — otevře se z Nastavení, teprve tady se ukážou 3 varianty.
struct AppIconPickerView: View {
    @AppStorage(AppSettingsKeys.appIconChoice) private var iconChoice = 0

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        iconChoice = option.rawValue
                        AppIconManager.apply(option)
                    } label: {
                        HStack(spacing: 12) {
                            Image(option.loginAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(option.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if iconChoice == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                Text("Změní ikonu na ploše i jahodu na přihlašovací obrazovce. Při změně ikony na ploše ukáže iOS potvrzovací okno.")
            }
        }
        .navigationTitle("Ikona aplikace")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
