import Foundation

/// Skládá název a popis události v Google Kalendáři z objednávky.
/// Čistá logika bez závislostí — pokrytá unit testy.
enum EventComposer {
    /// Délka události v kalendáři.
    static let eventDurationMinutes = 15

    /// Název události, např. „Jana Nováková – 3 kg jahod +vejce, sirup“.
    /// Bez jahod: „Jana Nováková – vejce, sirup“.
    static func title(for order: Order) -> String {
        var parts: [String] = []

        let kg = order.strawberryKg
        if kg > 0 {
            parts.append("\(CzechFormat.quantity(kg)) kg jahod")
        }

        let otherNames = order.nonStrawberryItems
            .map { $0.productName.lowercased(with: CzechFormat.locale) }
        if !otherNames.isEmpty {
            let joined = otherNames.joined(separator: ", ")
            parts.append(kg > 0 ? "+\(joined)" : joined)
        }

        let summary = parts.joined(separator: " ")
        return summary.isEmpty ? order.customerName : "\(order.customerName) – \(summary)"
    }

    /// Popis události: kompletní položky, poznámka, telefon, kdo zadal.
    static func description(for order: Order) -> String {
        var lines: [String] = ["Položky:"]
        for item in order.items {
            lines.append("• \(item.productName): \(CzechFormat.quantity(item.quantity)) \(item.unit)")
        }
        if let note = order.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Poznámka: \(note)")
        }
        if let phone = order.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("")
            lines.append("Telefon: \(phone)")
        }
        lines.append("")
        lines.append("Zadal(a): \(order.createdBy)")
        return lines.joined(separator: "\n")
    }

    /// Konec události = začátek + 15 minut.
    static func endDate(for order: Order) -> Date {
        order.pickupAt.addingTimeInterval(TimeInterval(eventDurationMinutes * 60))
    }
}
