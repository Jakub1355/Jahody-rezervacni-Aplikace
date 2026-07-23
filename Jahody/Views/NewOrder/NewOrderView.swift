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
    /// Přes `.sheet(item:)`, aby se data předala spolehlivě i hned po zavření diktování.
    @State private var unlistedProducts: UnlistedProducts?
    /// Diktování zvolilo „Uložit“ → uložit po zavření okna.
    @State private var shouldSaveAfterDictation = false

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
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !model.items.isEmpty {
                        BasketBar(items: model.items, total: model.total)
                    }
                }
            }
            .navigationTitle("Nová objednávka")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsDictation, onDismiss: {
                if shouldSaveAfterDictation {
                    shouldSaveAfterDictation = false
                    save()
                }
            }) {
                DictationSheet(
                    model: model,
                    products: products.activeProducts,
                    onSave: { shouldSaveAfterDictation = true }
                )
            }
            .sheet(item: $unlistedProducts) { offer in
                AddDictatedProductsSheet(items: offer.items, products: products)
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
        let order = model.buildOrder(createdBy: email)

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
            unlistedProducts = UnlistedProducts(items: unlisted)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

/// Obálka pro `.sheet(item:)` — nese seznam nadiktovaných produktů mimo číselník.
struct UnlistedProducts: Identifiable {
    let id = UUID()
    let items: [OrderItem]
}

/// Po uložení objednávky nabídne přidání nadiktovaných produktů, které nejsou
/// v číselníku — u každého se zvolí jednotka a (nepovinně) cena.
private struct AddDictatedProductsSheet: View {
    @ObservedObject var products: ProductStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [Draft]

    private struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var unit: ProductUnit
        var size: String
        var priceText: String
        var add: Bool
    }

    init(items: [OrderItem], products: ProductStore) {
        _products = ObservedObject(wrappedValue: products)
        _drafts = State(initialValue: items.map { item in
            Draft(
                name: item.productName,
                unit: ProductUnit(rawValue: item.unit) ?? .ks,
                size: item.size,
                priceText: "",
                add: true
            )
        })
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
                            TextField("Gramáž / balení (např. 250 ml)", text: $draft.size)
                            Picker("Počítá se po", selection: $draft.unit) {
                                ForEach(ProductUnit.allCases) { unit in
                                    Text(unit.label).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            TextField("Cena za balení (Kč, nepovinné)", text: $draft.priceText)
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
        }
    }

    private func addSelected() {
        for draft in drafts where draft.add {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            products.add(
                name: name,
                unit: draft.unit,
                size: draft.size.trimmingCharacters(in: .whitespaces),
                price: CzechFormat.parseQuantity(draft.priceText)
            )
        }
    }
}

/// Lišta „košíku" nahoře — ukazuje, co je zatím v objednávce, a průběžnou cenu.
private struct BasketBar: View {
    let items: [OrderItem]
    let total: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Košík", systemImage: "basket.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if total > 0 {
                    Text(CzechFormat.price(total))
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            HStack(spacing: 4) {
                                Image(ProductIcon.assetName(for: item.productName))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                Text(item.quantityLabel)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: items.map(\.id)) { _, _ in
                    // Vždy odrolovat na naposledy přidanou/upravenou položku.
                    guard let lastId = items.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .trailing) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
