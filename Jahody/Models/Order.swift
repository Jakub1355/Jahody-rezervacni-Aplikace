import Foundation

/// Stav objednávky. Fáze 2 počítá s přidáním hodnot `nachystana` a `vyzvednuta` —
/// proto je typ String-backed a Firestore ukládá surový řetězec.
enum OrderStatus: String, Codable, CaseIterable {
    case aktivni
    case zrusena

    var label: String {
        switch self {
        case .aktivni: return "Aktivní"
        case .zrusena: return "Zrušená"
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

/// Jedna položka objednávky, např. { productName: "Jahody", quantity: 3, unit: "kg" }.
struct OrderItem: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var productName: String
    var quantity: Double
    var unit: String

    // `id` je jen lokální (pro SwiftUI seznamy), do Firestore se neukládá.
    enum CodingKeys: String, CodingKey {
        case productName, quantity, unit
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
    /// Celkové kg jahod v objednávce (položky „Jahody“ v kg).
    var strawberryKg: Double {
        items
            .filter { $0.unit == ProductUnit.kg.rawValue && Self.isStrawberry(productName: $0.productName) }
            .reduce(0) { $0 + $1.quantity }
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
