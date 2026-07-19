import SwiftUI
import UIKit

/// Správa číselníku produktů: přidat, přejmenovat, cena, skrýt, seřadit.
struct ProductsSettingsView: View {
    @EnvironmentObject private var products: ProductStore

    @State private var renamedProduct: Product?
    @State private var renameText = ""
    @State private var showsAddSheet = false

    var body: some View {
        List {
            Section {
                ForEach(products.products) { product in
                    ProductRow(product: product) {
                        renamedProduct = product
                        renameText = product.name
                    }
                }
                .onMove { source, destination in
                    products.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("Cena je za jednotku (kg / ks / l). Podle ní se počítá cena objednávky. Vypnuté produkty se nenabízejí při zadávání, ale ve starých objednávkách zůstávají.")
            }
        }
        .navigationTitle("Produkty")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsAddSheet = true
                } label: {
                    Label("Přidat", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hotovo") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                }
            }
        }
        .alert("Přejmenovat produkt", isPresented: Binding(
            get: { renamedProduct != nil },
            set: { if !$0 { renamedProduct = nil } }
        )) {
            TextField("Název", text: $renameText)
            Button("Uložit") {
                if let product = renamedProduct,
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    products.rename(product, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                renamedProduct = nil
            }
            Button("Zrušit", role: .cancel) {
                renamedProduct = nil
            }
        }
        .sheet(isPresented: $showsAddSheet) {
            AddProductSheet()
                .presentationDetents([.medium])
        }
    }
}

/// Řádek produktu s editovatelnou cenou.
private struct ProductRow: View {
    let product: Product
    let onRename: () -> Void

    @EnvironmentObject private var products: ProductStore
    @State private var priceText: String
    @FocusState private var priceFocused: Bool

    init(product: Product, onRename: @escaping () -> Void) {
        self.product = product
        self.onRename = onRename
        _priceText = State(initialValue: product.price.map { CzechFormat.quantity($0) } ?? "")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .foregroundStyle(product.isActive ? .primary : .secondary)
                Text("za \(product.unit.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("cena", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .focused($priceFocused)
                .onChange(of: priceFocused) { _, focused in
                    if !focused { commitPrice() }
                }
            Text("Kč")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { product.isActive },
                set: { products.setActive(product, isActive: $0) }
            ))
            .labelsHidden()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Přejmenovat") { onRename() }
                .tint(.blue)
        }
    }

    private func commitPrice() {
        let trimmed = priceText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            products.setPrice(product, price: nil)
        } else if let value = CzechFormat.parseQuantity(trimmed) {
            products.setPrice(product, price: value)
        }
    }
}

private struct AddProductSheet: View {
    @EnvironmentObject private var products: ProductStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit: ProductUnit = .ks
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Název produktu", text: $name)
                Picker("Jednotka", selection: $unit) {
                    ForEach(ProductUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Cena za jednotku (Kč, nepovinné)", text: $priceText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Nový produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") {
                        products.add(
                            name: name.trimmingCharacters(in: .whitespaces),
                            unit: unit,
                            price: CzechFormat.parseQuantity(priceText)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
    }
}
