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
            strawberrySection
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
            NewProductSheet { name, unit, price in
                // Uloží nový produkt do číselníku a rovnou ho přidá do objednávky.
                let product = products.add(name: name, unit: unit, price: price)
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

    // MARK: Jahody
    private var strawberrySection: some View {
        Section {
            FlowLayout {
                ForEach(OrderFormModel.quickKgOptions, id: \.self) { kg in
                    Chip(
                        label: "\(CzechFormat.quantity(kg)) kg",
                        isSelected: model.strawberryKg == kg
                    ) {
                        model.strawberryText = CzechFormat.quantity(kg)
                    }
                }
            }
            TextField("Jiné množství, např. 0,5", text: $model.strawberryText)
                .keyboardType(.decimalPad)
                .frame(minHeight: 40)
        } header: {
            Label {
                Text("Jahody (kg)")
            } icon: {
                Image("ic_jahody").resizable().scaledToFit().frame(width: 20, height: 20)
            }
        }
    }

    // MARK: Další položky
    private var extraItemsSection: some View {
        Section("Další produkty") {
            let extraProducts = products.activeProducts
                .filter { !Order.isStrawberry(productName: $0.name) }
            if extraProducts.isEmpty {
                Text("Číselník produktů se načítá…")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(extraProducts) { product in
                        Chip(
                            label: product.name,
                            iconName: ProductIcon.assetName(for: product.name),
                            isSelected: model.extraItems.contains(where: { $0.productName == product.name })
                        ) {
                            model.addExtraItem(product: product)
                        }
                    }
                    Chip(label: "＋ Nový produkt", isSelected: false) {
                        showsNewProduct = true
                    }
                }
            }

            ForEach(model.extraItems) { item in
                HStack {
                    Image(ProductIcon.assetName(for: item.productName))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                    Text(item.productName)
                    Spacer()
                    Button {
                        model.changeQuantity(of: item, steps: -1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text("\(CzechFormat.quantity(item.quantity)) \(item.unit)")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 56)
                    Button {
                        model.changeQuantity(of: item, steps: 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 40)
            }
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
        let strawberryProduct = products.products.first { Order.isStrawberry(productName: $0.name) }
        let total = model.total(strawberryProduct: strawberryProduct)
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

/// Okno pro rychlé přidání nového produktu přímo z objednávky.
private struct NewProductSheet: View {
    /// (název, jednotka, cena?) potvrzeného produktu.
    let onCreate: (String, ProductUnit, Double?) -> Void
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
            } footer: {
                Text("Produkt se přidá do této objednávky i do číselníku, takže ho příště najdete mezi dalšími produkty.")
            }
            .navigationTitle("Nový produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") {
                        onCreate(name.trimmingCharacters(in: .whitespaces), unit, CzechFormat.parseQuantity(priceText))
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
