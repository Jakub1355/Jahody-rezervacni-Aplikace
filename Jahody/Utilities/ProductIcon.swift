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

    /// „🍓 3 kg  🥚 10 ks" — položky s ikonami pro přehled (textová varianta).
    static func summary(_ items: [OrderItem]) -> String {
        items
            .map { "\(emoji(for: $0.productName)) \(CzechFormat.quantity($0.quantity)) \($0.unit)" }
            .joined(separator: "  ")
    }

    /// Název vlastní kreslené ikonky produktu v Assets (pro přehled).
    static func assetName(for productName: String) -> String {
        let name = fold(productName)
        for (keys, asset) in assetMapping where keys.contains(where: { name.contains($0) }) {
            return asset
        }
        return "ic_ostatni"
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: CzechFormat.locale)
            .lowercased()
    }

    private static let assetMapping: [([String], String)] = [
        (["jahod"], "ic_jahody"),
        (["vajic", "vejc", "vajec"], "ic_vajicka"),
        (["sirup"], "ic_sirup"),
        (["marmelad", "dzem"], "ic_marmelada"),
        (["syr"], "ic_syr"),
        (["mlek", "mlik"], "ic_mleko"),
        (["tvaroh"], "ic_tvaroh"),
        (["brambor"], "ic_brambory"),
    ]

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
