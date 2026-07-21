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
    /// Dosud dokončený přepis (bez probíhající nahrávky) — pro živé zpracování celého textu.
    @State private var transcript = ""

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
                // Živé vyplňování během diktování — zpracujeme celý dosavadní text.
                guard speech.isRecording else { return }
                let combined = (transcript + " " + live).trimmingCharacters(in: .whitespaces)
                applyRecognized(DictationParser.parse(combined, products: products))
            }
            .onChange(of: speech.isRecording) { wasRecording, isRecording in
                // Po dokončení nahrávky si dokončený text připojíme k přepisu.
                if wasRecording && !isRecording {
                    let snippet = speech.transcript.trimmingCharacters(in: .whitespaces)
                    if !snippet.isEmpty {
                        transcript = (transcript + " " + snippet).trimmingCharacters(in: .whitespaces)
                        applyRecognized(DictationParser.parse(transcript, products: products))
                    }
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
                    applyAndDismiss()
                } label: {
                    Text("Použít do formuláře")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
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
            Text("Povolte mikrofon a rozpoznávání řeči v Nastavení iOS → Jahody.")
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

    /// Promítne rozpoznaný text do polí. Skalární hodnoty nastaví, jen když je
    /// parser našel (jinak ponechá). Produkty odrážejí celý dosavadní přepis.
    private func applyRecognized(_ result: DictationResult) {
        if let value = result.customerName, !value.isEmpty { name = value }
        if let value = result.phone, !value.isEmpty { phone = value }
        if let kg = result.strawberryKg, kg > 0 {
            strawberryText = CzechFormat.quantity(kg)
            showsStrawberry = true
        }
        if let day = result.pickupDay { pickupDay = Calendar.current.startOfDay(for: day) }
        if let minutes = result.pickupMinutes { pickupMinutes = minutes }
        if let value = result.note, !value.isEmpty { note = value }

        // Produkty odrážejí celý dosavadní přepis (autoritativně) — u známých
        // doplníme cenu i jednotku z číselníku.
        knownItems = result.extraItems.map { item in
            var updated = item
            if let product = products.first(where: {
                $0.name.caseInsensitiveCompare(item.productName) == .orderedSame
            }) {
                updated.unit = product.unit.rawValue
                updated.unitPrice = product.price
            }
            return updated
        }
        unknownItems = result.unknownItems
    }

    private func clearAll() {
        name = ""
        phone = ""
        strawberryText = ""
        note = ""
        knownItems = []
        unknownItems = []
        transcript = ""
        pickupDay = Calendar.current.startOfDay(for: Date())
        pickupMinutes = OrderFormModel.defaultPickupMinutes()
        showsStrawberry = false
        dismissKeyboard()
        speech.reset()
    }

    private func applyAndDismiss() {
        dismissKeyboard()
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

        speech.reset()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
