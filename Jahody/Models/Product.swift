import Foundation

enum ProductUnit: String, Codable, CaseIterable, Identifiable {
    case kg
    case ks
    case l

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Produkt v číselníku (kolekce `products`), editovatelný v Nastavení.
struct Product: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var unit: ProductUnit
    var isActive: Bool = true
    var sortOrder: Int = 0

    // `id` je ID dokumentu ve Firestore, do dat se neukládá.
    enum CodingKeys: String, CodingKey {
        case name, unit, isActive, sortOrder
    }
}

extension Product {
    /// Po kolika jednotkách se produkt obvykle objednává (krok tlačítek +/−
    /// a výchozí množství). Vajíčka po 10, ostatní po 1.
    var quantityStep: Double { ProductQuantity.step(forProductName: name) }
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
    /// Výchozí naplnění číselníku. Pevná ID dokumentů → seedování je idempotentní
    /// (dvě zařízení najednou nevytvoří duplicity).
    static let defaults: [Product] = [
        Product(id: "jahody", name: "Jahody", unit: .kg, isActive: true, sortOrder: 0),
        Product(id: "vajicka", name: "Vajíčka", unit: .ks, isActive: true, sortOrder: 1),
        Product(id: "sirup", name: "Sirup", unit: .ks, isActive: true, sortOrder: 2),
        Product(id: "marmelada", name: "Marmeláda", unit: .ks, isActive: true, sortOrder: 3),
        Product(id: "syr", name: "Sýr", unit: .ks, isActive: true, sortOrder: 4),
        Product(id: "mleko", name: "Mléko", unit: .l, isActive: true, sortOrder: 5),
        Product(id: "tvaroh", name: "Tvaroh", unit: .ks, isActive: true, sortOrder: 6),
    ]
}
