import SwiftUI

/// Pole formuláře objednávky — sdílená mezi „Nová objednávka“ a „Detail“.
/// Pořadí: zákazník → jahody → další produkty → den → čas → poznámka.
struct OrderFormFields: View {
    @ObservedObject var model: OrderFormModel
    /// Našeptávání jen při zadávání nové objednávky.
    var showSuggestions = true

    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var products: ProductStore
    @StateObject private var contacts = ContactsService()
    @State private var showsOtherDatePicker = false
    @State private var showsContactPicker = false
    @State private var showsNewProduct = false
    @State private var contactSuggestions: [CustomerSuggestion] = []
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            customerSection
            extraItemsSection
            pickupDaySection
            pickupTimeSection
            noteSection
            priceSection
        }
        .sheet(isPresented: $showsContactPicker) {
            ContactPicker { name, phone in
                if !name.isEmpty { model.customerName = name }
                if let phone, !phone.isEmpty { model.phone = phone }
                showsContactPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsNewProduct) {
            NewProductSheet { name, unit, size, price in
                // Uloží nový produkt do číselníku a rovnou ho přidá do objednávky.
                let product = products.add(name: name, unit: unit, size: size, price: price)
                model.addExtraItem(product: product)
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Zákazník
    private var customerSection: some View {
        Section("Zákazník") {
            TextField("Jméno", text: $model.customerName)
                .textContentType(.name)
                .focused($nameFocused)
                .frame(minHeight: 40)
                .onChange(of: model.customerName) { _, newName in
                    // Když zákazníka známe z historie, doplní se i telefon (pokud je prázdný).
                    if showSuggestions, model.phone.isEmpty,
                       let phone = orders.phone(forCustomerName: newName) {
                        model.phone = phone
                    }
                    // Našeptávání z kontaktů.
                    contactSuggestions = showSuggestions ? contacts.suggestions(matching: newName) : []
                }
                .onChange(of: nameFocused) { _, focused in
                    guard focused, showSuggestions else { return }
                    Task {
                        await contacts.ensureAccess()
                        contactSuggestions = contacts.suggestions(matching: model.customerName)
                    }
                }

            if showSuggestions, nameFocused {
                let history = orders.customerSuggestions(matching: model.customerName)
                let historyNames = Set(history.map { $0.name.lowercased() })
                ForEach(history) { suggestionRow($0, icon: "clock.arrow.circlepath") }
                ForEach(contactSuggestions.filter { !historyNames.contains($0.name.lowercased()) }) {
                    suggestionRow($0, icon: "person.crop.circle")
                }
            }

            TextField("Telefon (nepovinné)", text: $model.phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .frame(minHeight: 40)

            if showSuggestions {
                Button {
                    showsContactPicker = true
                } label: {
                    Label("Vybrat z kontaktů", systemImage: "person.crop.circle.badge.plus")
                        .frame(minHeight: 40)
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: CustomerSuggestion, icon: String) -> some View {
        Button {
            model.customerName = suggestion.name
            if let phone = suggestion.phone { model.phone = phone }
            nameFocused = false
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(suggestion.name)
                Spacer()
                if let phone = suggestion.phone {
                    Text(phone)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Produkty
    private var extraItemsSection: some View {
        Section("Produkty") {
            let catalog = products.activeProducts
            if catalog.isEmpty {
                Text("Číselník produktů se načítá…")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(catalog) { product in
                        ProductStepperChip(
                            product: product,
                            quantity: model.quantity(of: product),
                            onAdd: { model.addExtraItem(product: product) },
                            onIncrement: { model.increment(product) },
                            onDecrement: { model.decrement(product) }
                        )
                    }
                }
            }

            // Přidání nového produktu — pod nabídkou.
            Chip(label: "＋ Nový produkt", isSelected: false) {
                showsNewProduct = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Den vyzvednutí
    private var pickupDaySection: some View {
        Section("Den vyzvednutí") {
            FlowLayout {
                ForEach(0..<3, id: \.self) { offset in
                    let day = Calendar.current.date(
                        byAdding: .day,
                        value: offset,
                        to: Calendar.current.startOfDay(for: Date())
                    )!
                    Chip(
                        label: CzechFormat.relativeDayLabel(for: day),
                        isSelected: model.pickupDay == day
                    ) {
                        model.pickupDay = day
                        showsOtherDatePicker = false
                    }
                }
                Chip(label: "Jiný den…", isSelected: showsOtherDatePicker || !isQuickDay) {
                    showsOtherDatePicker.toggle()
                }
            }
            if showsOtherDatePicker || !isQuickDay {
                DatePicker(
                    "Datum",
                    selection: Binding(
                        get: { model.pickupDay },
                        set: { model.pickupDay = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, CzechFormat.locale)
            }
        }
    }

    // MARK: Čas vyzvednutí
    private var pickupTimeSection: some View {
        Section {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(OrderFormModel.timeSlots, id: \.self) { minutes in
                            Chip(
                                label: Self.timeLabel(minutes: minutes),
                                isSelected: model.pickupMinutes == minutes
                            ) {
                                model.pickupMinutes = minutes
                            }
                            .id(minutes)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    // Po zobrazení posunout pruh na aktuálně vybraný čas.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(model.pickupMinutes, anchor: .center)
                    }
                }
                .onChange(of: model.pickupMinutes) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        } header: {
            Text("Čas vyzvednutí — \(Self.timeLabel(minutes: model.pickupMinutes))")
        }
    }

    // MARK: Poznámka
    private var noteSection: some View {
        Section("Poznámka") {
            TextField("Volný text…", text: $model.note, axis: .vertical)
                .lineLimit(1...4)
                .frame(minHeight: 40)
        }
    }

    // MARK: Cena
    @ViewBuilder
    private var priceSection: some View {
        let total = model.total
        if total > 0 {
            Section {
                HStack {
                    Text("Cena objednávky").font(.headline)
                    Spacer()
                    Text(CzechFormat.price(total))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(minHeight: 40)
            }
        }
    }

    private var isQuickDay: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let offset = Calendar.current.dateComponents([.day], from: today, to: model.pickupDay).day ?? 99
        return (0...2).contains(offset)
    }

    private static func timeLabel(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Dlaždice produktu. Nevybraná = klepnutím se přidá; vybraná = má vlevo −
/// a vpravo + přímo na dlaždici (− na nule produkt odebere).
private struct ProductStepperChip: View {
    let product: Product
    let quantity: Double
    let onAdd: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        if quantity > 0 {
            HStack(spacing: 6) {
                Button { onDecrement() } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)

                Image(ProductIcon.assetName(for: product.name))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(CzechFormat.quantity(quantity))×")
                    .font(.subheadline.bold())
                    .monospacedDigit()

                Button { onIncrement() } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
        } else {
            Chip(
                label: product.name,
                iconName: ProductIcon.assetName(for: product.name),
                detail: product.size,
                isSelected: false,
                action: onAdd
            )
        }
    }
}

/// Okno pro rychlé přidání nového produktu přímo z objednávky.
private struct NewProductSheet: View {
    /// (název, jednotka, gramáž, cena?) potvrzeného produktu.
    let onCreate: (String, ProductUnit, String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit: ProductUnit = .ks
    @State private var size = ""
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } footer: {
                    Text("Produkt se přidá do této objednávky i do číselníku, takže ho příště najdete mezi produkty.")
                }
            }
            .navigationTitle("Nový produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") {
                        onCreate(
                            name.trimmingCharacters(in: .whitespaces),
                            unit,
                            size.trimmingCharacters(in: .whitespaces),
                            CzechFormat.parseQuantity(priceText)
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
