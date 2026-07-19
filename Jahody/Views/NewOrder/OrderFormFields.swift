import SwiftUI

/// Pole formuláře objednávky — sdílená mezi „Nová objednávka“ a „Detail“.
/// Pořadí: zákazník → jahody → další produkty → den → čas → poznámka.
struct OrderFormFields: View {
    @ObservedObject var model: OrderFormModel
    /// Našeptávání jen při zadávání nové objednávky.
    var showSuggestions = true

    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var products: ProductStore
    @State private var showsOtherDatePicker = false
    @State private var showsContactPicker = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            customerSection
            strawberrySection
            extraItemsSection
            pickupDaySection
            pickupTimeSection
            noteSection
        }
        .sheet(isPresented: $showsContactPicker) {
            ContactPicker { name, phone in
                if !name.isEmpty { model.customerName = name }
                if let phone, !phone.isEmpty { model.phone = phone }
                showsContactPicker = false
            }
            .ignoresSafeArea()
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
                    guard showSuggestions, model.phone.isEmpty,
                          let phone = orders.phone(forCustomerName: newName) else { return }
                    model.phone = phone
                }

            if showSuggestions, nameFocused {
                let suggestions = orders.customerSuggestions(matching: model.customerName)
                ForEach(suggestions) { suggestion in
                    Button {
                        model.customerName = suggestion.name
                        if let phone = suggestion.phone { model.phone = phone }
                        nameFocused = false
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
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

    // MARK: Jahody
    private var strawberrySection: some View {
        Section("Jahody (kg)") {
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
                            isSelected: model.extraItems.contains { $0.productName == product.name }
                        ) {
                            model.addExtraItem(product: product)
                        }
                    }
                }
            }

            ForEach(model.extraItems) { item in
                HStack {
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

    private var isQuickDay: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let offset = Calendar.current.dateComponents([.day], from: today, to: model.pickupDay).day ?? 99
        return (0...2).contains(offset)
    }

    private static func timeLabel(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
