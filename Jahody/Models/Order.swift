import Foundation

/// Stav objednávky. String-backed, Firestore ukládá surový řetězec.
enum OrderStatus: String, Codable, CaseIterable {
    case aktivni
    case zrusena
    /// Zákazník si objednávku vyzvedl — označeno potažením v přehledu.
    case vyzvednuta

    var label: String {
        switch self {
        case .aktivni: return "Aktivní"
        case .zrusena: return "Zrušená"
        case .vyzvednuta: return "Vyzvednuto"
        }
    }
}

/// Stav synchronizace objednávky se sdíleným Google Kalendářem.
enum CalendarSyncStatus: String, Codable {
    /// Čeká na zápis do kalendáře (nová/upravená/zrušená objednávka).
    case pending
    /// Kalendář odpovídá aktuálnímu stavu objednávky.
    case synced
    /// Opakovaně selhalo — v UI se ukazuje „nesynchronizováno s kalendářem“,
    /// zkusí se znovu při dalším spuštění/obnovení aplikace nebo ručně.
    case error
}

/// Jedna položka objednávky. `quantity` je počet balení (nebo kg/l u sypkých),
/// `unitPrice` je cena za jedno balení, `size` je gramáž balení („2,5 kg").
struct OrderItem: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var productName: String
    var quantity: Double
    var unit: String
    /// Gramáž balení v době objednání („2,5 kg", „250 ml"). Nepovinné.
    var size: String = ""
    /// Cena za jedno balení v době objednání (Kč). Nepovinné.
    var unitPrice: Double?

    // `id` je jen lokální (pro SwiftUI seznamy), do Firestore se neukládá.
    enum CodingKeys: String, CodingKey {
        case productName, quantity, unit, size, unitPrice
    }
}

extension OrderItem {
    /// Cena za tuto položku (počet × cena za balení), pokud je cena známá.
    var lineTotal: Double {
        quantity * (unitPrice ?? 0)
    }

    /// „2× 2,5 kg" pro balení, jinak „6 kg" / „10 ks".
    var quantityLabel: String {
        if !size.isEmpty {
            return "\(CzechFormat.quantity(quantity))× \(size)"
        }
        return "\(CzechFormat.quantity(quantity)) \(unit)"
    }
}

/// Objednávka — sdílený datový kontrakt s budoucím webovým klientem (viz zadání).
struct Order: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var customerName: String
    var phone: String?
    var items: [OrderItem]
    /// Kdy si zákazník přijede objednávku VYZVEDNOUT (ne kdy se sbírá).
    var pickupAt: Date
    var note: String?
    var status: OrderStatus = .aktivni
    /// E-mail člena rodiny, který objednávku zadal.
    var createdBy: String
    /// E-mail člena rodiny, který objednávku naposledy změnil (jeho zařízení
    /// zodpovídá za doběhnutí synchronizace s kalendářem).
    var updatedBy: String?
    /// ID události v Google Kalendáři — kvůli pozdější úpravě/smazání.
    var calendarEventId: String?
    var calendarSyncStatus: CalendarSyncStatus = .pending
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // `id` se do dokumentu neukládá — je to ID dokumentu ve Firestore.
    enum CodingKeys: String, CodingKey {
        case customerName, phone, items, pickupAt, note, status
        case createdBy, updatedBy, calendarEventId, calendarSyncStatus
        case createdAt, updatedAt
    }
}

extension Order {
    /// Celková cena objednávky (Kč), pokud je u položek známá cena.
    var totalPrice: Double {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    /// Má objednávka aspoň u jedné položky cenu?
    var hasPrice: Bool {
        items.contains { ($0.unitPrice ?? 0) > 0 }
    }

    /// Chybí u některé položky cena? (upozornění v přehledu)
    var hasMissingPrice: Bool {
        items.contains { ($0.unitPrice ?? 0) <= 0 }
    }

    /// Celkové kg jahod v objednávce — dopočítá se z gramáže balení
    /// (2× „Bedýnka 2,5 kg" = 5 kg). Starší objednávky měly jahody přímo v kg.
    var strawberryKg: Double {
        items
            .filter { Self.isStrawberry(productName: $0.productName) }
            .reduce(0) { sum, item in
                if let sizeKg = Product.kg(fromSize: item.size) {
                    return sum + item.quantity * sizeKg
                }
                if item.unit == ProductUnit.kg.rawValue {
                    return sum + item.quantity   // zpětná kompatibilita
                }
                return sum
            }
    }

    /// Jahodová balení v objednávce (pro rozpis „2× Bedýnka, 1× Panetka").
    var strawberryItems: [OrderItem] {
        items.filter { Self.isStrawberry(productName: $0.productName) }
    }

    /// Položky kromě jahod (pro název události „ +vejce, sirup“).
    var nonStrawberryItems: [OrderItem] {
        items.filter { !Self.isStrawberry(productName: $0.productName) }
    }

    static func isStrawberry(productName: String) -> Bool {
        productName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .hasPrefix("jahod")
    }
}
