import Foundation

/// České formátování dat a čísel na jednom místě.
enum CzechFormat {
    static let locale = Locale(identifier: "cs_CZ")

    /// „čtvrtek 23. 7.“
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EEEE d. M."
        return f
    }()

    /// „čtvrtek 23. 7. 2026“ (pro historii, kde záleží i na roce)
    static let dayWithYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EEEE d. M. yyyy"
        return f
    }()

    /// „17:00“
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "H:mm"
        return f
    }()

    /// Množství s desetinnou čárkou: 3 → „3“, 0.5 → „0,5“
    static let quantityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    static func quantity(_ value: Double) -> String {
        quantityFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Parsování množství z české klávesnice — akceptuje čárku i tečku („0,5“ i „0.5“).
    static func parseQuantity(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let number = quantityFormatter.number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// „Dnes“ / „Zítra“ / „Pozítří“ / „čtvrtek 23. 7.“
    static func relativeDayLabel(for date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        switch calendar.dateComponents([.day], from: today, to: day).day ?? Int.max {
        case 0: return "Dnes"
        case 1: return "Zítra"
        case 2: return "Pozítří"
        default: return dayFormatter.string(from: date)
        }
    }

    /// „3 kg jahod · 10 ks vajíčka“
    static func itemsSummary(_ items: [OrderItem]) -> String {
        items
            .map { "\(quantity($0.quantity)) \($0.unit) \($0.productName.lowercased(with: locale))" }
            .joined(separator: " · ")
    }
}
