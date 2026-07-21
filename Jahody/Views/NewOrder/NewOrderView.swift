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
    /// Nadiktované produkty mimo číselník — po uložení nabídneme jejich přidání.
    @State private var productsToOffer: [OrderItem] = []
    @State private var showsAddProducts = false

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
            .sheet(isPresented: $showsAddProducts) {
                AddDictatedProductsSheet(items: productsToOffer, products: products)
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

        // Nabídnout přidání nadiktovaných produktů, které nejsou v číselníku.
        let unlisted = order.items.filter { item in
            !Order.isStrawberry(productName: item.productName)
                && !item.productName.trimmingCharacters(in: .whitespaces).isEmpty
                && !products.products.contains {
                    $0.name.caseInsensitiveCompare(item.productName) == .orderedSame
                }
        }
        if !unlisted.isEmpty {
            productsToOffer = unlisted
            showsAddProducts = true
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

/// Po uložení objednávky nabídne přidání nadiktovaných produktů, které nejsou
/// v číselníku — u každého se zvolí jednotka a (nepovinně) cena.
private struct AddDictatedProductsSheet: View {
    let items: [OrderItem]
    @ObservedObject var products: ProductStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [Draft] = []

    private struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var unit: ProductUnit
        var priceText: String
        var add: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tyto produkty jste nadiktovali, ale nejsou v číselníku. Chcete je přidat, aby se příště samy nabízely?")
                        .foregroundStyle(.secondary)
                }

                ForEach($drafts) { $draft in
                    Section {
                        Toggle("Přidat do číselníku", isOn: $draft.add)
                        if draft.add {
                            TextField("Název produktu", text: $draft.name)
                            Picker("Jednotka", selection: $draft.unit) {
                                ForEach(ProductUnit.allCases) { unit in
                                    Text(unit.label).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            TextField("Cena za jednotku (Kč, nepovinné)", text: $draft.priceText)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text(draft.name.isEmpty ? "Nový produkt" : draft.name)
                    }
                }
            }
            .navigationTitle("Nové produkty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") {
                        addSelected()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Teď ne") { dismiss() }
                }
            }
            .onAppear {
                guard drafts.isEmpty else { return }
                drafts = items.map { item in
                    Draft(
                        name: item.productName,
                        unit: ProductUnit(rawValue: item.unit) ?? .ks,
                        priceText: "",
                        add: true
                    )
                }
            }
        }
    }

    private func addSelected() {
        for draft in drafts where draft.add {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            products.add(name: name, unit: draft.unit, price: CzechFormat.parseQuantity(draft.priceText))
        }
    }
}
