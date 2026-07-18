import SwiftUI

/// Detail objednávky: úprava všech polí (propíše se do kalendářní události),
/// Zavolat / SMS, zrušení objednávky.
struct OrderDetailView: View {
    let orderId: String

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var products: ProductStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
                        Section("Kontakt") {
                            Button {
                                call(phone, scheme: "tel")
                            } label: {
                                Label("Zavolat \(phone)", systemImage: "phone.fill")
                                    .frame(minHeight: 40)
                            }
                            Button {
                                call(phone, scheme: "sms")
                            } label: {
                                Label("SMS", systemImage: "message.fill")
                                    .frame(minHeight: 40)
                            }
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
        let strawberryProduct = products.products.first { Order.isStrawberry(productName: $0.name) }
        let updated = model.apply(to: order, strawberryProduct: strawberryProduct)
        do {
            try orders.update(updated, editedBy: email)
        } catch {
            errorMessage = "Uložení se nepovedlo: \(error.localizedDescription)"
            return
        }
        errorMessage = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await app.calendarSync.syncPending() }
        dismiss()
    }

    private func cancelOrder(_ order: Order) {
        guard let email = auth.user?.email else { return }
        do {
            try orders.cancel(order, editedBy: email)
        } catch {
            errorMessage = "Zrušení se nepovedlo: \(error.localizedDescription)"
            return
        }
        Task { await app.calendarSync.syncPending() }
        dismiss()
    }

    private func call(_ phone: String, scheme: String) {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "\(scheme)://\(cleaned)") {
            openURL(url)
        }
    }
}
