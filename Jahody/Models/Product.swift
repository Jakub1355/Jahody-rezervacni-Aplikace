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
