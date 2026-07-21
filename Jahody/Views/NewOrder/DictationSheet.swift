import SwiftUI
import UIKit

/// Nadiktování objednávky. Diktovat lze **po částech a v jakémkoliv pořadí** —
/// rozpoznané hodnoty se doplní do editovatelných polí níže. Každou hodnotu lze
/// ještě **ručně opravit** (např. překlep ve jméně) a teprve pak poslat do formuláře.
/// Produkty mimo číselník spadnou do sekce „Další“.
struct DictationSheet: View {
    @ObservedObject var model: OrderFormModel
    /// Aktivní produkty pro rozpoznání dalších položek.
    let products: [Product]
    /// Zavolá se, když uživatel zvolí „Uložit objednávku“ rovnou z diktování.
    var onSave: () -> Void = {}

    @StateObject private var speech = SpeechDictationService()
    @Environment(\.dismiss) private var dismiss

    // Editovatelná rozpoznaná pole (naplní se z formuláře a doplňují diktováním).
    @State private var name = ""
    @State private var phone = ""
    @State private var strawberryText = ""
    @State private var pickupDay = Calendar.current.startOfDay(for: Date())
    @State private var pickupMinutes = OrderFormModel.defaultPickupMinutes()
    /// Produkty z číselníku (každý vlastní řádek s ručním množstvím).
    @State private var knownItems: [OrderItem] = []
    /// Produkty mimo číselník („Další“).
    @State private var unknownItems: [OrderItem] = []
    @State private var note = ""
    @State private var didSeed = false
    /// Řádek jahod se ukáže, až když jsou nadiktované/zadané (ať se hned nezobrazuje „0 kg“).
    @State private var showsStrawberry = false

    // Snímek hodnot pořízený na začátku nahrávky. Živé rozpoznávání jen tento
    // základ **doplňuje** — dřív rozpoznané položky se tak nemažou, jen přibývají.
    @State private var base = Snapshot()

    private struct Snapshot {
        var name = ""
        var phone = ""
        var strawberryText = ""
        var showsStrawberry = false
        var pickupDay = Calendar.current.startOfDay(for: Date())
        var pickupMinutes = OrderFormModel.defaultPickupMinutes()
        var note = ""
        var knownItems: [OrderItem] = []
        var unknownItems: [OrderItem] = []
    }

    private enum Field: Hashable { case name, phone, strawberry, note }
    @FocusState private var focusedField: Field?

    private var hasAnyValue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            || !phone.trimmingCharacters(in: .whitespaces).isEmpty
            || !strawberryText.trimmingCharacters(in: .whitespaces).isEmpty
            || !knownItems.isEmpty
            || !unknownItems.isEmpty
            || !note.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !speech.isAvailable {
                    unavailableView
                } else if speech.permissionDenied {
                    permissionDeniedView
                } else {
                    mainForm
                }
            }
            .navigationTitle("Nadiktovat objednávku")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        speech.reset()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hotovo") { dismissKeyboard() }
                }
            }
            .onChange(of: speech.transcript) { _, live in
                // Živé vyplňování během mluvení — základ (dřívější) jen doplňujeme.
                guard speech.isRecording else { return }
                applyFromSnippet(live)
            }
            .onChange(of: speech.isRecording) { wasRecording, isRecording in
                if !wasRecording && isRecording {
                    // Začátek nahrávky: uložíme aktuální stav jako pevný základ.
                    base = currentSnapshot()
                } else if wasRecording && !isRecording {
                    // Konec: promítneme finální text a připravíme se na další nahrávku.
                    applyFromSnippet(speech.transcript)
                    base = currentSnapshot()
                    speech.reset()
                }
            }
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                name = model.customerName
                phone = model.phone
                strawberryText = model.strawberryText
                pickupDay = model.pickupDay
                pickupMinutes = model.pickupMinutes
                note = model.note
                showsStrawberry = !strawberryText.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    // MARK: Hlavní formulář

    private var mainForm: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    micButton
                    micStatus
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Diktujte klidně po částech, v jakémkoliv pořadí (např. „Jana Nováková 777 123 456“, pak „tři kila jahod“, pak „zítra ve tři“). Rozpoznané údaje se doplní níže a můžete je upravit.")
            }

            recognizedSection

            if !unknownItems.isEmpty {
                unknownSection
            }

            Section {
                Button {
                    apply(thenSave: true)
                } label: {
                    Text("Uložit objednávku")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(speech.isRecording || !canSaveOrder)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button {
                    apply(thenSave: false)
                } label: {
                    Text("Jen upravit ve formuláři")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .disabled(speech.isRecording)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if hasAnyValue {
                    Button("Vymazat vše", role: .destructive) {
                        clearAll()
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Editovatelná rozpoznaná pole

    private var recognizedSection: some View {
        Section("Rozpoznáno — upravte podle potřeby") {
            HStack {
                Text("Jméno").foregroundStyle(.secondary)
                TextField("jméno zákazníka", text: $name)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
            }

            HStack {
                Text("Telefon").foregroundStyle(.secondary)
                TextField("telefon", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .phone)
            }

            if showsStrawberry {
                HStack {
                    Image("ic_jahody").resizable().scaledToFit().frame(width: 24, height: 24)
                    Text("Jahody").foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", text: $strawberryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .strawberry)
                        .frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }
            }

            ForEach($knownItems) { $item in
                HStack {
                    Image(ProductIcon.assetName(for: item.productName))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(item.productName).foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", value: $item.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text(unitLabel(item.unit)).foregroundStyle(.secondary)
                }
            }
            .onDelete { knownItems.remove(atOffsets: $0) }

            DatePicker("Den", selection: $pickupDay, displayedComponents: .date)
                .environment(\.locale, CzechFormat.locale)

            DatePicker("Čas", selection: timeBinding, displayedComponents: .hourAndMinute)
                .environment(\.locale, CzechFormat.locale)

            HStack(alignment: .top) {
                Text("Poznámka").foregroundStyle(.secondary)
                TextField("poznámka", text: $note, axis: .vertical)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .note)
            }
        }
    }

    // MARK: Produkty mimo číselník

    private var unknownSection: some View {
        Section {
            ForEach($unknownItems) { $item in
                HStack(spacing: 8) {
                    TextField("název produktu", text: $item.productName)
                    Spacer(minLength: 4)
                    TextField("0", value: $item.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Picker("", selection: $item.unit) {
                        ForEach(ProductUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .onDelete { unknownItems.remove(atOffsets: $0) }
        } header: {
            Text("Další (nové produkty)")
        } footer: {
            Text("Tyto produkty nejsou v číselníku. Po uložení objednávky nabídneme jejich přidání (s jednotkou a cenou).")
        }
    }

    // MARK: Mikrofon

    private var micButton: some View {
        Button {
            dismissKeyboard()
            speech.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(speech.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .overlay {
                if speech.isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 8)
                        .frame(width: 116, height: 116)
                        .scaleEffect(speech.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Zastavit diktování" : "Přidat diktováním")
    }

    private var micStatus: some View {
        Group {
            if speech.isRecording {
                VStack(spacing: 6) {
                    Text("Poslouchám…")
                        .font(.headline)
                        .foregroundStyle(.red)
                    if !speech.transcript.isEmpty {
                        Text(speech.transcript)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Klepněte na mikrofon a diktujte")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Diktování není dostupné",
            systemImage: "mic.slash",
            description: Text("Na tomto zařízení není dostupné rozpoznávání české řeči. Objednávku vyplňte ručně.")
        )
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Chybí oprávnění", systemImage: "mic.slash")
        } description: {
            Text("Povolte mikrofon a rozpoznávání řeči v Nastavení iOS → Jahoda.")
        } actions: {
            Button("Otevřít Nastavení") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Pomocné

    /// Spolehlivě schová klávesnici bez ohledu na to, které pole je právě aktivní
    /// (číselná pole u produktů nejsou vázaná na `focusedField`).
    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private func unitLabel(_ raw: String) -> String {
        ProductUnit(rawValue: raw)?.label ?? raw
    }

    /// Čas (převod minut ↔ Date pro DatePicker).
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: pickupMinutes / 60,
                    minute: pickupMinutes % 60,
                    second: 0,
                    of: pickupDay
                ) ?? pickupDay
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                pickupMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    // MARK: Akce

    /// Snímek aktuálních polí (pevný základ pro následující nahrávku).
    private func currentSnapshot() -> Snapshot {
        Snapshot(
            name: name, phone: phone, strawberryText: strawberryText,
            showsStrawberry: showsStrawberry, pickupDay: pickupDay,
            pickupMinutes: pickupMinutes, note: note,
            knownItems: knownItems, unknownItems: unknownItems
        )
    }

    /// Promítne rozpoznaný **úsek** do polí: začne z pevného základu (`base`) a
    /// jen ho doplní. Dřívější položky se tak nemažou, nová nahrávka jen přidá.
    private func applyFromSnippet(_ text: String) {
        let result = DictationParser.parse(
            text.trimmingCharacters(in: .whitespaces), products: products
        )

        name = (result.customerName?.isEmpty == false) ? result.customerName! : base.name
        phone = (result.phone?.isEmpty == false) ? result.phone! : base.phone
        if let kg = result.strawberryKg, kg > 0 {
            strawberryText = CzechFormat.quantity(kg)
            showsStrawberry = true
        } else {
            strawberryText = base.strawberryText
            showsStrawberry = base.showsStrawberry
        }
        pickupDay = result.pickupDay.map { Calendar.current.startOfDay(for: $0) } ?? base.pickupDay
        pickupMinutes = result.pickupMinutes ?? base.pickupMinutes
        note = (result.note?.isEmpty == false) ? result.note! : base.note

        knownItems = mergedItems(base.knownItems, result.extraItems.map(withCatalogInfo))
        unknownItems = mergedItems(base.unknownItems, result.unknownItems)
    }

    /// Přidá nové položky k základu a u existujících (stejný název) jen upraví
    /// množství. Nikdy nic neodebírá.
    private func mergedItems(_ existing: [OrderItem], _ additions: [OrderItem]) -> [OrderItem] {
        var result = existing
        for item in additions {
            if let index = result.firstIndex(where: {
                $0.productName.caseInsensitiveCompare(item.productName) == .orderedSame
            }) {
                result[index].quantity = item.quantity
                result[index].unit = item.unit
                if item.unitPrice != nil { result[index].unitPrice = item.unitPrice }
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// Doplní jednotku a cenu z číselníku (pokud produkt existuje).
    private func withCatalogInfo(_ item: OrderItem) -> OrderItem {
        var updated = item
        if let product = products.first(where: {
            $0.name.caseInsensitiveCompare(item.productName) == .orderedSame
        }) {
            updated.unit = product.unit.rawValue
            updated.unitPrice = product.price
        }
        return updated
    }

    private func clearAll() {
        name = ""
        phone = ""
        strawberryText = ""
        note = ""
        knownItems = []
        unknownItems = []
        base = Snapshot()
        pickupDay = Calendar.current.startOfDay(for: Date())
        pickupMinutes = OrderFormModel.defaultPickupMinutes()
        showsStrawberry = false
        dismissKeyboard()
        speech.reset()
    }

    /// Jde objednávku uložit rovnou z diktování? (jméno + aspoň jedna položka)
    private var canSaveOrder: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasStrawberry = (CzechFormat.parseQuantity(strawberryText) ?? 0) > 0
        let hasItems = knownItems.contains { $0.quantity > 0 }
            || unknownItems.contains {
                !$0.productName.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0
            }
        return hasName && (hasStrawberry || hasItems)
    }

    private func applyToModel() {
        model.customerName = name.trimmingCharacters(in: .whitespaces)
        model.phone = phone.trimmingCharacters(in: .whitespaces)
        model.strawberryText = strawberryText.trimmingCharacters(in: .whitespaces)
        model.pickupDay = Calendar.current.startOfDay(for: pickupDay)
        model.pickupMinutes = pickupMinutes
        model.note = note.trimmingCharacters(in: .whitespaces)

        let dictated = (knownItems + unknownItems.map { item -> OrderItem in
            var updated = item
            updated.productName = item.productName.trimmingCharacters(in: .whitespaces)
            return updated
        }).filter { !$0.productName.isEmpty && $0.quantity > 0 }

        // Nadiktované položky přidáme/aktualizujeme ve formuláři (nepřepíšeme případné ruční).
        var merged = model.extraItems
        for item in dictated {
            if let index = merged.firstIndex(where: {
                $0.productName.caseInsensitiveCompare(item.productName) == .orderedSame
            }) {
                merged[index] = item
            } else {
                merged.append(item)
            }
        }
        model.extraItems = merged
    }

    /// Doplní data do formuláře a volitelně rovnou spustí uložení objednávky.
    private func apply(thenSave: Bool) {
        dismissKeyboard()
        applyToModel()
        if thenSave { onSave() }
        speech.reset()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
