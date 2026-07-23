import Foundation

/// Denní přehledy: seskupení objednávek podle dne vyzvednutí a součty položek.
/// Čistá logika bez závislostí — pokrytá unit testy.
enum DailySummary {
    /// Skupina objednávek jednoho dne.
    struct DayGroup: Identifiable {
        let day: Date            // startOfDay
        let orders: [Order]      // seřazené podle času vyzvednutí

        var id: Date { day }

        /// Součet kg jahod aktivních objednávek dne — podle něj se plánuje sběr.
        var strawberryKg: Double {
            DailySummary.strawberryKg(orders)
        }

        /// Součty ostatních položek aktivních objednávek, např. „vajíčka 30 ks · sirup 2 ks“.
        var otherItemsSummary: String {
            DailySummary.otherItemsSummary(orders)
        }
    }

    /// Seskupí objednávky podle dne `pickupAt` (vzestupně) a uvnitř dne podle času.
    static func groupByDay(_ orders: [Order], calendar: Calendar = .current) -> [DayGroup] {
        let grouped = Dictionary(grouping: orders) { calendar.startOfDay(for: $0.pickupAt) }
        return grouped
            .map { day, dayOrders in
                DayGroup(day: day, orders: dayOrders.sorted { $0.pickupAt < $1.pickupAt })
            }
            .sorted { $0.day < $1.day }
    }

    /// Součet kg jahod přes aktivní objednávky (zrušené se nepočítají).
    static func strawberryKg(_ orders: [Order]) -> Double {
        orders
            .filter { $0.status == .aktivni }
            .reduce(0) { $0 + $1.strawberryKg }
    }

    /// Součty ostatních položek aktivních objednávek podle (název, jednotka, gramáž).
    static func otherItemTotals(_ orders: [Order]) -> [(name: String, quantity: Double, unit: String, size: String)] {
        aggregate(orders) { $0.nonStrawberryItems }
    }

    /// Součty jahodových balení (pro rozpis „2× Bedýnka · 1× Panetka").
    static func strawberryPackageTotals(_ orders: [Order]) -> [(name: String, quantity: Double, unit: String, size: String)] {
        aggregate(orders) { $0.strawberryItems }
    }

    private static func aggregate(
        _ orders: [Order],
        items: (Order) -> [OrderItem]
    ) -> [(name: String, quantity: Double, unit: String, size: String)] {
        struct Key: Hashable {
            let name: String
            let unit: String
            let size: String
        }
        var totals: [Key: Double] = [:]
        var firstSeen: [Key: Int] = [:]
        var counter = 0

        for order in orders where order.status == .aktivni {
            for item in items(order) {
                let key = Key(name: item.productName, unit: item.unit, size: item.size)
                totals[key, default: 0] += item.quantity
                if firstSeen[key] == nil {
                    firstSeen[key] = counter
                    counter += 1
                }
            }
        }
        return totals
            .sorted { (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0) }
            .map { (name: $0.key.name, quantity: $0.value, unit: $0.key.unit, size: $0.key.size) }
    }

    /// Popisek množství: „2× 2,5 kg" pro balení, jinak „30 ks".
    static func quantityLabel(quantity: Double, unit: String, size: String) -> String {
        if !size.isEmpty {
            return "\(CzechFormat.quantity(quantity))× \(size)"
        }
        return "\(CzechFormat.quantity(quantity)) \(unit)"
    }

    /// „vajíčka 30 ks · sirup 2× 500 ml“ (prázdný řetězec, pokud nic není)
    static func otherItemsSummary(_ orders: [Order]) -> String {
        otherItemTotals(orders)
            .map { "\($0.name.lowercased(with: CzechFormat.locale)) \(quantityLabel(quantity: $0.quantity, unit: $0.unit, size: $0.size))" }
            .joined(separator: " · ")
    }
}
