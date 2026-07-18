import SwiftUI

/// Hlavní obrazovka — bleskové zadání objednávky během telefonátu (cíl do 15 s).
struct NewOrderView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var products: ProductStore

    @StateObject private var model = OrderFormModel()
    @State private var savedBannerVisible = false
    @State private var errorMessage: String?
    @State private var showsDictation = false

    var body: some View {
        NavigationStack {
            Form {
                // Rychlé nadiktování celé objednávky (jméno, telefon, kdy, kolik).
                Section {
                    Button {
                        showsDictation = true
                    } label: {
                        Label("Nadiktovat objednávku", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                }

                OrderFormFields(model: model)

                Section {
                    Button {
                        save()
                    } label: {
                        Text("Uložit objednávku")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .disabled(!model.canSave)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nová objednávka")
            .sheet(isPresented: $showsDictation) {
                DictationSheet(model: model, products: products.activeProducts)
            }
            .overlay(alignment: .top) {
                if savedBannerVisible {
                    Label("Objednávka uložena", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func save() {
        guard let email = auth.user?.email else { return }
        let strawberryProduct = products.products.first { Order.isStrawberry(productName: $0.name) }
        let order = model.buildOrder(createdBy: email, strawberryProduct: strawberryProduct)

        do {
            // Zápis do Firestore projde okamžitě (i offline)…
            try orders.add(order)
        } catch {
            errorMessage = "Uložení se nepovedlo: \(error.localizedDescription)"
            return
        }

        errorMessage = nil
        model.reset()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { savedBannerVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedBannerVisible = false }
        }

        // …a událost v kalendáři se vytvoří asynchronně, uložení nesmí blokovat.
        Task { await app.calendarSync.syncPending() }
    }
}
