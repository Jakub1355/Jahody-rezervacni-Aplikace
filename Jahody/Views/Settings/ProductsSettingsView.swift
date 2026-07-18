import SwiftUI

/// Správa číselníku produktů: přidat, přejmenovat, skrýt, seřadit.
struct ProductsSettingsView: View {
    @EnvironmentObject private var products: ProductStore

    @State private var renamedProduct: Product?
    @State private var renameText = ""
    @State private var showsAddSheet = false

    var body: some View {
        List {
            Section {
                ForEach(products.products) { product in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.name)
                                .foregroundStyle(product.isActive ? .primary : .secondary)
                            Text(product.unit.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { product.isActive },
                            set: { products.setActive(product, isActive: $0) }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Přejmenovat") {
                            renamedProduct = product
                            renameText = product.name
                        }
                        .tint(.blue)
                    }
                }
                .onMove { source, destination in
                    products.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("Vypnuté produkty se nenabízejí při zadávání objednávky, ale ve starých objednávkách zůstávají.")
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

private struct AddProductSheet: View {
    @EnvironmentObject private var products: ProductStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit: ProductUnit = .ks

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
            }
            .navigationTitle("Nový produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") {
                        products.add(name: name.trimmingCharacters(in: .whitespaces), unit: unit)
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
