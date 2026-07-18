import Foundation

/// Výsledek rozpoznání nadiktované objednávky. Vyplní se jen to, co parser
/// spolehlivě najde — zbytek uživatel doplní/opraví ručně.
struct DictationResult {
    var customerName: String?
    var phone: String?
    var strawberryKg: Double?
    /// Den vyzvednutí (start dne).
    var pickupDay: Date?
    /// Čas vyzvednutí v minutách od půlnoci (zarovnaný na 30 minut).
    var pickupMinutes: Int?
    var extraItems: [OrderItem] = []
    var note: String?
    /// Původní přepis řeči — ať se nic neztratí, i když parser něco mine.
    var transcript: String = ""
}

/// Rozpozná českou nadiktovanou objednávku na strukturovaná pole.
/// Heuristika pro běžné formulace („Jana Nováková, telefon 777 123 456,
/// přijede zítra v pět, chce tři kila jahod“). Čistá logika bez UI — testovatelná.
enum DictationParser {

    // MARK: - Veřejné API

    static func parse(
        _ transcript: String,
        products: [Product] = Product.defaults,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DictationResult {
        var result = DictationResult()
        result.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Telefon vytáhneme z textu a odstraníme, ať neplete čísla dál.
        var working = transcript
        if let (phone, range) = extractPhone(from: working) {
            result.phone = phone
            working.replaceSubrange(range, with: " ")
        }

        // 2) Poznámka: vše za slovem „poznámka“.
        if let note = extractNote(from: working) {
            result.note = note.text
            working.replaceSubrange(note.range, with: " ")
        }

        // 3) Tokenizace zbytku.
        let tokens = tokenize(working)
        let folded = tokens.map(fold)
        let morning = folded.contains { $0.hasPrefix("rano") || $0.hasPrefix("dopoledne") }

        // 4) Den, čas, jahody, další položky.
        result.pickupDay = extractDay(folded: folded, now: now, calendar: calendar)
        if let minutes = extractTime(tokens: tokens, folded: folded, morning: morning) {
            result.pickupMinutes = snapTo30(minutes)
        }
        let strawberry = extractStrawberryKg(tokens: tokens, folded: folded, products: products)
        result.strawberryKg = strawberry.kg
        result.extraItems = extractExtraItems(
            folded: folded,
            products: products,
            consumed: strawberry.consumed
        )

        // 5) Jméno = vedoucí slova před prvním číslem/klíčovým slovem.
        result.customerName = extractName(tokens: tokens, folded: folded)

        return result
    }

    // MARK: - Telefon

    static func extractPhone(from text: String) -> (phone: String, range: Range<String.Index>)? {
        // Volitelná předvolba + aspoň 9 číslic, číslice můžou být oddělené mezerami.
        let pattern = "\\+?\\d[\\d ]{7,}\\d"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Vybereme výskyt s nejvíce číslicemi (a aspoň 9).
        let best = matches
            .map { ($0, nsText.substring(with: $0.range)) }
            .filter { $0.1.filter(\.isNumber).count >= 9 }
            .max { $0.1.filter(\.isNumber).count < $1.1.filter(\.isNumber).count }

        guard let (match, raw) = best,
              let range = Range(match.range, in: text) else { return nil }

        let phone = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        return (phone, range)
    }

    // MARK: - Poznámka

    private static func extractNote(from text: String) -> (text: String, range: Range<String.Index>)? {
        let lower = fold(text)
        guard let keywordRange = lower.range(of: "poznamka") else { return nil }
        // Odpovídající rozsah v původním textu (fold nemění délku ani pozice znaků).
        let distance = lower.distance(from: lower.startIndex, to: keywordRange.lowerBound)
        guard let start = text.index(text.startIndex, offsetBy: distance, limitedBy: text.endIndex)
        else { return nil }

        let after = text.index(start, offsetBy: "poznamka".count, limitedBy: text.endIndex) ?? text.endIndex
        let noteText = text[after...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-"))
        guard !noteText.isEmpty else { return nil }
        return (noteText, start..<text.endIndex)
    }

    // MARK: - Den

    private static let weekdayStems: [(stem: String, weekday: Int)] = [
        ("pondel", 2), ("uter", 3), ("stred", 4), ("ctvrtek", 5), ("ctvrtk", 5),
        ("patek", 6), ("patk", 6), ("sobot", 7), ("nedel", 1),
    ]

    private static func extractDay(folded: [String], now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        for token in folded {
            if token.hasPrefix("dnes") { return today }
            if token.hasPrefix("zitra") { return calendar.date(byAdding: .day, value: 1, to: today) }
            if token.hasPrefix("pozitri") { return calendar.date(byAdding: .day, value: 2, to: today) }
        }
        for token in folded {
            if let match = weekdayStems.first(where: { token.hasPrefix($0.stem) }) {
                return nextDate(weekday: match.weekday, from: today, calendar: calendar)
            }
        }
        return nil
    }

    /// Nejbližší budoucí (nebo dnešní) den se zadaným dnem v týdnu.
    private static func nextDate(weekday: Int, from today: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: today)
        let offset = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    // MARK: - Čas

    private static let ordinalsForHalf: [String: Int] = [
        "druhe": 2, "druha": 2, "treti": 3, "ctvrte": 4, "ctvrta": 4,
        "pate": 5, "pata": 5, "seste": 6, "sesta": 6, "sedme": 7, "sedma": 7,
        "osme": 8, "osma": 8, "devate": 9, "devata": 9, "desate": 10, "desata": 10,
        "jedenacte": 11, "dvanacte": 12,
    ]

    private static func extractTime(tokens: [String], folded: [String], morning: Bool) -> Int? {
        func finalize(hour: Int, minute: Int) -> Int {
            var h = hour
            if h >= 1 && h <= 7 && !morning { h += 12 } // odpolední vyzvednutí
            return h * 60 + minute
        }

        for i in tokens.indices {
            let t = folded[i]

            // „17:30“ / „17.30“
            if let (h, m) = parseClock(tokens[i]) {
                return finalize(hour: h, minute: m)
            }

            // „půl páté“ = 16:30
            if t == "pul", i + 1 < tokens.count, let ord = ordinalsForHalf[folded[i + 1]] {
                return finalize(hour: ord - 1, minute: 30)
            }

            // Holá hodina 13–23 jen s minutami (např. „sedmnáct třicet“, „17 30“),
            // ať se „dvacet kila“ neplete s hodinou.
            if let h = intValue(tokens[i], folded: t), h >= 13, h <= 23,
               i + 1 < tokens.count, let m = minuteValue(tokens[i + 1], folded: folded[i + 1]) {
                return finalize(hour: h, minute: m)
            }

            // „v pět“, „ve tři“, „o pět“ (+ volitelně minuty), „v pět hodin“
            if t == "v" || t == "ve" || t == "o" {
                if i + 1 < tokens.count, let h = intValue(tokens[i + 1], folded: folded[i + 1]), h >= 0, h <= 23 {
                    let m = (i + 2 < tokens.count ? minuteValue(tokens[i + 2], folded: folded[i + 2]) : nil) ?? 0
                    return finalize(hour: h, minute: m)
                }
            }

            // „<hodina> hodin“
            if let h = intValue(tokens[i], folded: t), h >= 0, h <= 23,
               i + 1 < tokens.count, folded[i + 1].hasPrefix("hodin") {
                return finalize(hour: h, minute: 0)
            }
        }
        return nil
    }

    private static func parseClock(_ token: String) -> (hour: Int, minute: Int)? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        let separators = CharacterSet(charactersIn: ":.")
        let parts = cleaned.components(separatedBy: separators)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    // MARK: - Jahody (kg)

    private static let kgMarkers = ["kilo", "kila", "kilogram", "kilogramy", "kilogramu", "kg"]

    /// Vrátí kg jahod a indexy tokenů, které množství zabralo (ať se nepočítají znovu).
    private static func extractStrawberryKg(
        tokens: [String],
        folded: [String],
        products: [Product]
    ) -> (kg: Double?, consumed: Set<Int>) {
        var consumed = Set<Int>()

        guard let markerIndex = folded.firstIndex(where: { marker in
            kgMarkers.contains { marker == $0 || marker.hasPrefix($0) }
        }) else {
            return (nil, consumed)
        }

        // Pokud za „kila“ následuje jiný produkt (např. „dvě kila sýra“),
        // nejde o jahody — nechá to na scanu dalších položek.
        if markerIndex + 1 < folded.count {
            let next = folded[markerIndex + 1]
            let nonStrawberry = products.filter { !Order.isStrawberry(productName: $0.name) }
            if nonStrawberry.contains(where: { next.hasPrefix(productStem($0.name)) }) {
                return (nil, consumed)
            }
        }

        // Množství čteme zpět před markerem: „tři a půl kila“, „půl kila“, „1,5 kg“.
        var value = 0.0
        var found = false
        var j = markerIndex - 1
        if j >= 0, folded[j] == "pul" {
            value += 0.5
            found = true
            consumed.insert(j)
            j -= 1
            if j >= 0, folded[j] == "a" { consumed.insert(j); j -= 1 }
        }
        if j >= 0, let whole = doubleValue(tokens[j], folded: folded[j]) {
            value += whole
            found = true
            consumed.insert(j)
        }
        consumed.insert(markerIndex)

        return found && value > 0 ? (value, consumed) : (nil, consumed)
    }

    // MARK: - Další položky

    private static func extractExtraItems(
        folded: [String],
        products: [Product],
        consumed: Set<Int>
    ) -> [OrderItem] {
        let candidates = products
            .filter { $0.isActive && !Order.isStrawberry(productName: $0.name) }
            .map { (product: $0, stem: productStem($0.name)) }

        var items: [OrderItem] = []
        var usedProductNames = Set<String>()

        for i in folded.indices where !consumed.contains(i) {
            guard let quantity = doubleValue(nil, folded: folded[i]), quantity > 0 else { continue }
            // Název produktu smí následovat do 3 tokenů za číslem.
            for lookahead in 1...3 where i + lookahead < folded.count {
                let word = folded[i + lookahead]
                guard word.count >= 3 else { continue }
                if let match = candidates.first(where: { word.hasPrefix($0.stem) }),
                   !usedProductNames.contains(match.product.name) {
                    items.append(OrderItem(
                        productName: match.product.name,
                        quantity: quantity,
                        unit: match.product.unit.rawValue
                    ))
                    usedProductNames.insert(match.product.name)
                    break
                }
            }
        }
        return items
    }

    // MARK: - Jméno

    private static let nameStopWords: Set<String> = {
        var set: Set<String> = [
            "telefon", "cislo", "mobil", "dnes", "zitra", "pozitri",
            "chce", "chteel", "chtel", "bere", "prijede", "prijel", "prijedou",
            "hodin", "pul", "v", "ve", "o", "a", "poznamka", "kg",
        ]
        set.formUnion(kgMarkers)
        set.formUnion(weekdayStems.map(\.stem))
        return set
    }()

    private static let nameFillerWords: Set<String> = [
        "objednavka", "objednavku", "pro", "jmeno", "jmenem",
        "pan", "pani", "zakaznik", "je", "tady", "ma",
    ]

    private static func extractName(tokens: [String], folded: [String]) -> String? {
        var collected: [String] = []
        for i in tokens.indices {
            let f = folded[i]
            if collected.isEmpty, nameFillerWords.contains(f) { continue }
            // Konec jména: číslo nebo klíčové slovo.
            if doubleValue(tokens[i], folded: f) != nil { break }
            if nameStopWords.contains(f) || weekdayStems.contains(where: { f.hasPrefix($0.stem) }) { break }
            guard f.first?.isLetter == true else { break }
            collected.append(capitalizeFirst(tokens[i]))
            if collected.count >= 3 { break }
        }
        let name = collected.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - Čísla

    private static let numberWords: [String: Double] = [
        "nula": 0, "jeden": 1, "jedna": 1, "jedno": 1, "jednu": 1,
        "dva": 2, "dve": 2, "tri": 3, "ctyri": 4, "pet": 5, "sest": 6,
        "sedm": 7, "osm": 8, "devet": 9, "deset": 10, "jedenact": 11,
        "dvanact": 12, "trinact": 13, "ctrnact": 14, "patnact": 15,
        "sestnact": 16, "sedmnact": 17, "osmnact": 18, "devatenact": 19, "dvacet": 20,
    ]

    private static let minuteWords: [String: Int] = [
        "patnact": 15, "tricet": 30, "ctyricet": 40, "padesat": 50,
    ]

    /// Číselná hodnota tokenu (číslice „3“/„0,5“ nebo slovo „tři“/„půl“).
    private static func doubleValue(_ token: String?, folded: String) -> Double? {
        if folded == "pul" { return 0.5 }
        if let number = numberWords[folded] { return number }
        // Číslice s desetinnou čárkou/tečkou.
        let source = token ?? folded
        let normalized = source
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
            .replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), normalized.allSatisfy({ $0.isNumber || $0 == "." }) {
            return value
        }
        return nil
    }

    private static func intValue(_ token: String, folded: String) -> Int? {
        guard let value = doubleValue(token, folded: folded), value == value.rounded() else { return nil }
        return Int(value)
    }

    private static func minuteValue(_ token: String, folded: String) -> Int? {
        if let m = minuteWords[folded] { return m }
        if let value = intValue(token, folded: folded), (0...59).contains(value) { return value }
        return nil
    }

    // MARK: - Pomocné

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: CzechFormat.locale)
            .lowercased()
    }

    private static func productStem(_ name: String) -> String {
        String(fold(name).prefix(3))
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ";:!?—-\"'()")) }
            .map { token -> String in
                // Odstraní tečku/čárku na okrajích, ale ponechá desetinnou uvnitř („0,5“).
                var t = token
                while let first = t.first, first == "." || first == "," { t.removeFirst() }
                while let last = t.last, last == "." || last == "," { t.removeLast() }
                return t
            }
            .filter { !$0.isEmpty }
    }

    private static func capitalizeFirst(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

    /// Zarovná minuty na nejbližší 30minutový slot v rozsahu 7:00–19:30.
    private static func snapTo30(_ minutes: Int) -> Int {
        let clamped = max(7 * 60, min(19 * 60 + 30, minutes))
        return Int((Double(clamped) / 30).rounded()) * 30
    }
}
