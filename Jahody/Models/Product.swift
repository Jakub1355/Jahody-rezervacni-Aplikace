import Foundation

enum ProductUnit: String, Codable, CaseIterable, Identifiable {
    case kg
    case ks
    case l

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Produkt v číselníku (kolekce `products`), editovatelný v Nastavení.
/// Prodává se po **baleních** — `price` je cena za jedno balení (ne za kg),
/// `size` je popis gramáže („2,5 kg", „250 ml", „balení"). Množství v objednávce
/// je počet balení; celková cena = počet × price.
struct Product: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var unit: ProductUnit
    /// Gramáž / velikost balení pro zobrazení (např. „2,5 kg", „500 ml", „balení").
    var size: String = ""
    var isActive: Bool = true
    var sortOrder: Int = 0
    /// Cena za jedno balení (Kč). Nepovinné.
    var price: Double?

    // `id` je ID dokumentu ve Firestore, do dat se neukládá.
    enum CodingKeys: String, CodingKey {
        case name, unit, size, isActive, sortOrder, price
    }
}

extension Product {
    /// Po kolika kusech se produkt obvykle objednává (krok tlačítek +/−
    /// a výchozí množství). Vajíčka po 10, ostatní po 1.
    var quantityStep: Double { ProductQuantity.step(forProductName: name) }

    /// Kolik kg je v jednom balení (pro součet jahod v přehledu) — z gramáže „2,5 kg".
    var kgPerPackage: Double? { Self.kg(fromSize: size) }

    /// Vytáhne kg z popisu gramáže („2,5 kg" → 2.5, „500 ml" → nil).
    static func kg(fromSize size: String) -> Double? {
        let lower = size.lowercased()
        guard lower.contains("kg") else { return nil }
        let number = lower
            .replacingOccurrences(of: "kg", with: "")
            .trimmingCharacters(in: .whitespaces)
        return CzechFormat.parseQuantity(number)
    }
}

/// Krok množství podle názvu produktu — funguje i pro už uložené produkty
/// (neukládá se do dat, odvozuje se z názvu).
enum ProductQuantity {
    static func step(forProductName name: String) -> Double {
        let n = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: CzechFormat.locale)
            .lowercased()
        if n.hasPrefix("vaj") || n.contains("vejc") || n.contains("vajec") {
            return 10   // vajíčka po deseti
        }
        return 1
    }
}

extension Product {
    /// Výchozí naplnění číselníku podle reálného ceníku farmy. Pevná ID dokumentů →
    /// seedování i „Načíst ceník" jsou idempotentní.
    static let defaults: [Product] = [
        // Jahody — dvě balení (počítají se po kusech, kg se dopočítá z gramáže).
        Product(id: "jahody-bedynka", name: "Jahody – Bedýnka", unit: .ks, size: "2,5 kg", sortOrder: 0, price: 429),
        Product(id: "jahody-panetka", name: "Jahody – Panetka", unit: .ks, size: "0,5 kg", sortOrder: 1, price: 89),

        // Brambory a mléko — po jednotce (kg / l).
        Product(id: "brambory", name: "Brambory BIO", unit: .kg, size: "", sortOrder: 2, price: 30),
        Product(id: "mleko", name: "Mléko", unit: .l, size: "", sortOrder: 3, price: 40),
        Product(id: "vejce", name: "Vejce", unit: .ks, size: "", sortOrder: 4, price: 8),

        // Sirupy.
        Product(id: "sirup-250", name: "Sirup 250 ml", unit: .ks, size: "250 ml", sortOrder: 5, price: 79),
        Product(id: "sirup-500", name: "Sirup 500 ml", unit: .ks, size: "500 ml", sortOrder: 6, price: 159),

        // Marmelády.
        Product(id: "marmelada-130", name: "Marmeláda jahoda-rybíz 130 g", unit: .ks, size: "130 g", sortOrder: 7, price: 69),
        Product(id: "marmelada-270", name: "Marmeláda jahoda-rybíz 270 g", unit: .ks, size: "270 g", sortOrder: 8, price: 109),

        // Lyofilizované.
        Product(id: "lyo-jahody-15", name: "Lyofilizované jahody 15 g", unit: .ks, size: "15 g", sortOrder: 9, price: 75),
        Product(id: "lyo-jahody-25", name: "Lyofilizované jahody 25 g", unit: .ks, size: "25 g", sortOrder: 10, price: 119),
        Product(id: "lyo-mix-20", name: "Lyofilizovaný mix 20 g", unit: .ks, size: "20 g", sortOrder: 11, price: 75),
        Product(id: "lyo-mix-35", name: "Lyofilizovaný mix 35 g", unit: .ks, size: "35 g", sortOrder: 12, price: 119),
        Product(id: "lyo-svestky-25", name: "Lyofilizované švestky 25 g", unit: .ks, size: "25 g", sortOrder: 13, price: 75),
        Product(id: "lyo-svestky-40", name: "Lyofilizované švestky 40 g", unit: .ks, size: "40 g", sortOrder: 14, price: 119),

        // Mléčné.
        Product(id: "maslo", name: "Máslo", unit: .ks, size: "200 g", sortOrder: 15, price: 99),
        Product(id: "ghi", name: "Ghí", unit: .ks, size: "250 g", sortOrder: 16, price: 159),
        Product(id: "tvaroh-bily", name: "Tvaroh bílý", unit: .ks, size: "250 g", sortOrder: 17, price: 55),
        Product(id: "tvarohacek-vanilka", name: "Tvaroháček vanilka", unit: .ks, size: "300 ml", sortOrder: 18, price: 55),
        Product(id: "tvarohacek-cokolada", name: "Tvaroháček čokoláda", unit: .ks, size: "300 ml", sortOrder: 19, price: 55),

        // Jogurty.
        Product(id: "jogurt-ovocny", name: "Jogurt ovocný", unit: .ks, size: "300 ml", sortOrder: 20, price: 39),
        Product(id: "jogurt-bily", name: "Jogurt bílý", unit: .ks, size: "300 ml", sortOrder: 21, price: 29),
        Product(id: "jogurt-cokoladovy", name: "Jogurt čokoládový", unit: .ks, size: "300 ml", sortOrder: 22, price: 45),

        // Nápoje.
        Product(id: "napoj-ovocny", name: "Nápoj ovocný", unit: .ks, size: "500 ml", sortOrder: 23, price: 45),
        Product(id: "napoj-bily", name: "Nápoj bílý", unit: .ks, size: "500 ml", sortOrder: 24, price: 35),
        Product(id: "napoj-vanilkovy", name: "Nápoj vanilkový", unit: .ks, size: "500 ml", sortOrder: 25, price: 55),
        Product(id: "napoj-cokoladovy", name: "Nápoj čokoládový", unit: .ks, size: "500 ml", sortOrder: 26, price: 55),

        // Ostatní.
        Product(id: "granola", name: "Granola", unit: .ks, size: "balení", sortOrder: 27, price: 185),
        Product(id: "nite", name: "Nitě", unit: .ks, size: "450 g", sortOrder: 28, price: 200),
        Product(id: "korbacky-nite", name: "Korbáčky – Nitě", unit: .ks, size: "200 g", sortOrder: 29, price: 100),
        Product(id: "spaliky", name: "Špalíky", unit: .ks, size: "450 g", sortOrder: 30, price: 250),
    ]
}
