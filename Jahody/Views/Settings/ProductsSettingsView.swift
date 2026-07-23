import SwiftUI
import UIKit

/// Správa číselníku produktů: přidat, přejmenovat, cena, skrýt, seřadit.
struct ProductsSettingsView: View {
    @EnvironmentObject private var products: ProductStore

    @State private var showsAddSheet = false
    @State private var productPendingDeletion: Product?

    var body: some View {
        List {
            Section {
                ForEach(products.products) { product in
                    ProductRow(
                        product: product,
                        onDelete: {
                            productPendingDeletion = product
                        }
                    )
                }
                .onMove { source, destination in
                    products.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("Klepnutím upravíte název, gramáž i cenu. Cena je za balení. Vypnuté produkty se nenabízejí při zadávání, ale ve starých objednávkách zůstávají.")
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
        .confirmationDialog(
            "Smazat produkt?",
            isPresented: Binding(
                get: { productPendingDeletion != nil },
                set: { if !$0 { productPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: productPendingDeletion
        ) { product in
            Button("Smazat \(product.name)", role: .destructive) {
                products.delete(product)
                productPendingDeletion = nil
            }
            Button("Zrušit", role: .cancel) {
                productPendingDeletion = nil
            }
        } message: { product in
            Text("Produkt „\(product.name)“ se trvale odebere z číselníku. Staré objednávky zůstanou nedotčené.")
        }
        .sheet(isPresented: $showsAddSheet) {
            AddProductSheet()
                .presentationDetents([.medium])
        }
    }
}

/// Řádek produktu s editovatelným názvem, gramáží a cenou.
private struct ProductRow: View {
    let product: Product
    let onDelete: () -> Void

    @EnvironmentObject private var products: ProductStore
    @State private var nameText: String
    @State private var sizeText: String
    @State private var priceText: String
    @FocusState private var focusedField: Field?

    private enum Field { case name, size, price }

    init(product: Product, onDelete: @escaping () -> Void) {
        self.product = product
        self.onDelete = onDelete
        _nameText = State(initialValue: product.name)
        _sizeText = State(initialValue: product.size)
        _priceText = State(initialValue: product.price.map { CzechFormat.quantity($0) } ?? "")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Název produktu", text: $nameText)
                    .foregroundStyle(product.isActive ? .primary : .secondary)
                    .focused($focusedField, equals: .name)
                TextField("gramáž (např. 250 ml)", text: $sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .focused($focusedField, equals: .size)
            }
            Spacer(minLength: 8)
            TextField("cena", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .focused($focusedField, equals: .price)
            Text("Kč")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { product.isActive },
                set: { products.setActive(product, isActive: $0) }
            ))
            .labelsHidden()
        }
        .onChange(of: focusedField) { previous, _ in
            switch previous {
            case .name: commitName()
            case .size: commitSize()
            case .price: commitPrice()
            case nil: break
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Smazat", role: .destructive) { onDelete() }
        }
    }

    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != product.name {
            products.rename(product, to: trimmed)
        }
    }

    private func commitSize() {
        let trimmed = sizeText.trimmingCharacters(in: .whitespaces)
        if trimmed != product.size {
            products.setSize(product, size: trimmed)
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
    @State private var size = ""
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Název produktu", text: $name)
                TextField("Gramáž / balení (např. 250 ml)", text: $size)
                Picker("Počítá se po", selection: $unit) {
                    ForEach(ProductUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Cena za balení (Kč, nepovinné)", text: $priceText)
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
                            size: size.trimmingCharacters(in: .whitespaces),
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
