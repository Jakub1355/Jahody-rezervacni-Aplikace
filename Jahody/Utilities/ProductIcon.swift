import Foundation

/// Emoji ikonka pro produkt — ať je v přehledu na první pohled vidět,
/// co je objednané (🍓 jahody, 🥚 vajíčka, 🧀 sýr…).
enum ProductIcon {
    /// Vrátí emoji podle názvu produktu (odolné vůči diakritice a velikosti písmen).
    /// Pro neznámé/vlastní produkty vrátí obecný košík.
    static func emoji(for productName: String) -> String {
        let name = productName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: CzechFormat.locale)
            .lowercased()

        // Pořadí záleží — konkrétnější shody dřív.
        for (keys, icon) in mapping {
            if keys.contains(where: { name.contains($0) }) {
                return icon
            }
        }
        return "🧺"
    }

    /// „🍓 3 kg  🥚 10 ks" — položky s ikonami pro přehled.
    static func summary(_ items: [OrderItem]) -> String {
        items
            .map { "\(emoji(for: $0.productName)) \(CzechFormat.quantity($0.quantity)) \($0.unit)" }
            .joined(separator: "  ")
    }

    /// Klíčové části názvů (bez diakritiky) → emoji.
    private static let mapping: [([String], String)] = [
        (["jahod"], "🍓"),
        (["vajic", "vejc", "vajec"], "🥚"),
        (["sirup"], "🍾"),          // vysoká láhev (emoji nejdou přebarvit)
        (["marmelad", "dzem"], "🍒"), // červená
        (["med"], "🍯"),
        (["syr"], "🧀"),
        (["mlek", "mlik"], "🥛"),
        (["tvaroh"], "🥣"),
        (["maslo"], "🧈"),
        (["brambor"], "🥔"),
        (["jablk", "jablc"], "🍎"),
        (["okurk"], "🥒"),
        (["rajc"], "🍅"),
        (["chleb", "peciv"], "🍞"),
        (["kure", "kuris", "maso"], "🍗"),
    ]
}
