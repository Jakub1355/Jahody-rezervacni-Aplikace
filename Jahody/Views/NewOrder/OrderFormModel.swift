import Foundation
import SwiftUI

/// Stav formuláře objednávky — sdílený mezi „Nová objednávka“ a „Detail“.
@MainActor
final class OrderFormModel: ObservableObject {
    @Published var customerName = ""
    @Published var phone = ""
    /// Množství jahod jako text (česká klávesnice s čárkou, např. „0,5“).
    @Published var strawberryText = ""
    /// Den vyzvednutí (start dne).
    @Published var pickupDay: Date
    /// Čas vyzvednutí — minuty od půlnoci (po 30 minutách).
    @Published var pickupMinutes: Int = 16 * 60
    /// Další položky kromě jahod.
    @Published var extraItems: [OrderItem] = []
    @Published var note = ""

    /// Rychlé chipy pro jahody.
    static let quickKgOptions: [Double] = [1, 2, 3, 5]
    /// Sloty po 30 minutách 7:00–19:30.
    static let timeSlots: [Int] = Array(stride(from: 7 * 60, through: 19 * 60 + 30, by: 30))

    init() {
        pickupDay = Calendar.current.startOfDay(for: Date())
    }

    var strawberryKg: Double {
        CzechFormat.parseQuantity(strawberryText) ?? 0
    }

    var pickupAt: Date {
        Calendar.current.date(byAdding: .minute, value: pickupMinutes, to: pickupDay) ?? pickupDay
    }

    var trimmedName: String {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Jméno + aspoň jedna položka.
    var canSave: Bool {
        !trimmedName.isEmpty && (strawberryKg > 0 || !extraItems.isEmpty)
    }

    // MARK: - Položky

    func items(strawberryProduct: Product?) -> [OrderItem] {
        var items: [OrderItem] = []
        if strawberryKg > 0 {
            items.append(OrderItem(
                productName: strawberryProduct?.name ?? "Jahody",
                quantity: strawberryKg,
                unit: ProductUnit.kg.rawValue
            ))
        }
        items.append(contentsOf: extraItems)
        return items
    }

    func addExtraItem(product: Product) {
        let step = product.quantityStep
        if let index = extraItems.firstIndex(where: { $0.productName == product.name }) {
            extraItems[index].quantity += step
        } else {
            extraItems.append(OrderItem(productName: product.name, quantity: step, unit: product.unit.rawValue))
        }
    }

    /// Změní množství o `steps` kroků (krok podle produktu — vajíčka po 10).
    func changeQuantity(of item: OrderItem, steps: Double) {
        guard let index = extraItems.firstIndex(where: { $0.id == item.id }) else { return }
        let step = ProductQuantity.step(forProductName: item.productName)
        let newQuantity = extraItems[index].quantity + steps * step
        if newQuantity <= 0 {
            extraItems.remove(at: index)
        } else {
            extraItems[index].quantity = newQuantity
        }
    }

    // MARK: - Načtení / sestavení objednávky

    func load(from order: Order) {
        customerName = order.customerName
        phone = order.phone ?? ""
        note = order.note ?? ""

        let calendar = Calendar.current
        pickupDay = calendar.startOfDay(for: order.pickupAt)
        let components = calendar.dateComponents([.hour, .minute], from: order.pickupAt)
        pickupMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if let strawberries = order.items.first(where: { Order.isStrawberry(productName: $0.productName) }) {
            strawberryText = CzechFormat.quantity(strawberries.quantity)
        } else {
            strawberryText = ""
        }
        extraItems = order.nonStrawberryItems
    }

    /// Nová objednávka z formuláře.
    func buildOrder(createdBy email: String, strawberryProduct: Product?) -> Order {
        Order(
            customerName: trimmedName,
            phone: normalizedPhone,
            items: items(strawberryProduct: strawberryProduct),
            pickupAt: pickupAt,
            note: normalizedNote,
            status: .aktivni,
            createdBy: email,
            updatedBy: email,
            calendarSyncStatus: .pending
        )
    }

    /// Propíše formulář do existující objednávky (Detail → Uložit změny).
    func apply(to order: Order, strawberryProduct: Product?) -> Order {
        var updated = order
        updated.customerName = trimmedName
        updated.phone = normalizedPhone
        updated.items = items(strawberryProduct: strawberryProduct)
        updated.pickupAt = pickupAt
        updated.note = normalizedNote
        return updated
    }

    /// Zapíše rozpoznaná pole z nadiktované objednávky. Co diktát nenašel,
    /// zůstane beze změny — vše jde následně ručně upravit.
    func apply(dictation result: DictationResult) {
        if let name = result.customerName, !name.isEmpty {
            customerName = name
        }
        if let phone = result.phone, !phone.isEmpty {
            self.phone = phone
        }
        if let kg = result.strawberryKg, kg > 0 {
            strawberryText = CzechFormat.quantity(kg)
        }
        if let day = result.pickupDay {
            pickupDay = Calendar.current.startOfDay(for: day)
        }
        if let minutes = result.pickupMinutes {
            pickupMinutes = minutes
        }
        for item in result.extraItems {
            if let index = extraItems.firstIndex(where: { $0.productName == item.productName }) {
                extraItems[index].quantity = item.quantity
            } else {
                extraItems.append(item)
            }
        }
        if let note = result.note, !note.isEmpty {
            self.note = note
        }
    }

    func reset() {
        customerName = ""
        phone = ""
        strawberryText = ""
        pickupDay = Calendar.current.startOfDay(for: Date())
        pickupMinutes = 16 * 60
        extraItems = []
        note = ""
    }

    private var normalizedPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
