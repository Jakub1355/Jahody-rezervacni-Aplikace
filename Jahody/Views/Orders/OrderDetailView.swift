import SwiftUI
import UIKit

/// Detail objednávky: úprava všech polí (propíše se do kalendářní události),
/// Zavolat / zpráva (SMS, WhatsApp, Messenger), zrušení objednávky.
struct OrderDetailView: View {
    let orderId: String

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var products: ProductStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Přednastavená zpráva zákazníkovi (upravitelná v Nastavení).
    @AppStorage(AppSettingsKeys.readyMessage) private var readyMessage = AppSettingsKeys.defaultReadyMessage

    @StateObject private var model = OrderFormModel()
    @State private var isLoaded = false
    @State private var showsCancelConfirmation = false
    @State private var errorMessage: String?

    /// Aktuální stav objednávky (živě z Firestore listeneru).
    private var order: Order? {
        (orders.upcomingOrders + orders.historyOrders).first { $0.id == orderId }
    }

    var body: some View {
        Group {
            if let order {
                Form {
                    if order.status == .zrusena {
                        Section {
                            Label("Objednávka je zrušená", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    } else if order.calendarSyncStatus != .synced {
                        Section {
                            HStack {
                                Label(
                                    "Nesynchronizováno s kalendářem",
                                    systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                                )
                                .foregroundStyle(order.calendarSyncStatus == .error ? .red : .orange)
                                Spacer()
                                Button("Zkusit znovu") {
                                    Task { await app.calendarSync.retry(order: order) }
                                }
                                .font(.callout)
                            }
                        }
                    }

                    OrderFormFields(model: model, showSuggestions: false)

                    // Kontakt na objednávajícího
                    if let phone = order.phone, !phone.isEmpty {
                        Section {
                            Button {
                                call(phone)
                            } label: {
                                Label("Zavolat \(phone)", systemImage: "phone.fill")
                                    .frame(minHeight: 44)
                            }
                            Button {
                                sendSMS(to: phone)
                            } label: {
                                Label("SMS zpráva", systemImage: "message.fill")
                                    .frame(minHeight: 44)
                            }
                            Button {
                                sendWhatsApp(to: phone)
                            } label: {
                                Label("WhatsApp", systemImage: "phone.bubble.fill")
                                    .frame(minHeight: 44)
                                    .tint(.green)
                            }
                            Button {
                                sendMessenger()
                            } label: {
                                Label("Messenger", systemImage: "bubble.left.and.bubble.right.fill")
                                    .frame(minHeight: 44)
                                    .tint(.blue)
                            }
                        } header: {
                            Text("Kontakt")
                        } footer: {
                            Text("Odešle se zpráva: \(readyMessage)\nText upravíte v Nastavení. (Messenger zprávu na telefonní číslo nepředvyplní, proto se zkopíruje a otevře aplikace, kde ji vložíte.)")
                        }
                    }

                    if order.status == .aktivni {
                        Section {
                            Button {
                                saveChanges(to: order)
                            } label: {
                                Text("Uložit změny")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.borderedProminent)
                            .listRowInsets(EdgeInsets())
                            .disabled(!model.canSave)

                            Button(role: .destructive) {
                                showsCancelConfirmation = true
                            } label: {
                                Label("Zrušit objednávku", systemImage: "trash")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }

                    Section {
                        LabeledContent("Zadal(a)", value: order.createdBy)
                        LabeledContent(
                            "Vytvořeno",
                            value: "\(CzechFormat.dayFormatter.string(from: order.createdAt)) \(CzechFormat.timeFormatter.string(from: order.createdAt))"
                        )
                    }
                    .font(.footnote)
                }
                .navigationTitle(order.customerName)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if !isLoaded {
                        model.load(from: order)
                        isLoaded = true
                    }
                }
                .confirmationDialog(
                    "Zrušit objednávku?",
                    isPresented: $showsCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Zrušit objednávku", role: .destructive) {
                        cancelOrder(order)
                    }
                    Button("Zpět", role: .cancel) {}
                } message: {
                    Text("Objednávka se označí jako zrušená a událost se smaže z kalendáře.")
                }
            } else {
                ContentUnavailableView("Objednávka nenalezena", systemImage: "questionmark.circle")
            }
        }
    }

    private func saveChanges(to order: Order) {
        guard let email = auth.user?.email else { return }
        let updated = model.apply(to: order)
        do {
            try orders.update(updated, editedBy: email)
        } catch {
            errorMessage = "Uložení se nepovedlo: \(error.localizedDescription)"
            return
        }
        errorMessage = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await app.calendarSync.syncNow(updated) }
        dismiss()
    }

    private func cancelOrder(_ order: Order) {
        guard let email = auth.user?.email else { return }
        var cancelled = order
        cancelled.status = .zrusena
        do {
            try orders.cancel(order, editedBy: email)
        } catch {
            errorMessage = "Zrušení se nepovedlo: \(error.localizedDescription)"
            return
        }
        // Smazání události v kalendáři rovnou pro tuto zrušenou objednávku.
        Task { await app.calendarSync.syncNow(cancelled) }
        dismiss()
    }

    private func call(_ phone: String) {
        if let url = URL(string: "tel:\(digitsAndPlus(phone))") {
            openURL(url)
        }
    }

    private func sendSMS(to phone: String) {
        let body = readyMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digitsAndPlus(phone))&body=\(body)") {
            openURL(url)
        }
    }

    private func sendWhatsApp(to phone: String) {
        let text = readyMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(internationalDigits(phone))?text=\(text)") {
            openURL(url)
        }
    }

    private func sendMessenger() {
        // Messenger neumí otevřít chat na telefonní číslo s předvyplněnou zprávou,
        // proto text zkopírujeme a otevřeme aplikaci — uživatel vybere kontakt a vloží.
        UIPasteboard.general.string = readyMessage
        if let app = URL(string: "fb-messenger://"), UIApplication.shared.canOpenURL(app) {
            openURL(app)
        } else if let web = URL(string: "https://www.messenger.com/") {
            openURL(web)
        }
    }

    /// Ponechá jen číslice (a úvodní +) — pro tel:/sms:.
    private func digitsAndPlus(_ phone: String) -> String {
        var out = ""
        for (index, ch) in phone.enumerated() {
            if ch.isNumber { out.append(ch) }
            else if ch == "+" && index == 0 { out.append(ch) }
        }
        return out
    }

    /// Mezinárodní číslo bez + a mezer (pro WhatsApp). 9místné české číslo dostane 420.
    private func internationalDigits(_ phone: String) -> String {
        var digits = phone.filter(\.isNumber)
        if digits.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
        if digits.count == 9 { digits = "420" + digits }
        return digits
    }
}
