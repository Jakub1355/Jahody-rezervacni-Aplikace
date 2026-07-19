import SwiftUI
import UIKit

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
    /// Zvýší se po uložení → formulář se odscrolluje nahoru.
    @State private var scrollToTopTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                    .id("top")

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
                .onChange(of: scrollToTopTrigger) { _, _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
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
        dismissKeyboard()
        model.reset()
        scrollToTopTrigger += 1   // zpět na začátek formuláře
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { savedBannerVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedBannerVisible = false }
        }

        // …a událost v kalendáři se vytvoří asynchronně (rovnou tato objednávka),
        // uložení tím nikdy neblokuje.
        Task { await app.calendarSync.syncNow(order) }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}
