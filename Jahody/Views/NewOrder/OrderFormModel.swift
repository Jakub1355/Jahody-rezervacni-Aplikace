import Foundation
import SwiftUI

/// Stav formuláře objednávky — sdílený mezi „Nová objednávka“ a „Detail“.
/// Jahody i ostatní produkty jsou položky v `items` (počítají se po baleních).
@MainActor
final class OrderFormModel: ObservableObject {
    @Published var customerName = ""
    @Published var phone = ""
    /// Den vyzvednutí (start dne).
    @Published var pickupDay: Date
    /// Čas vyzvednutí — minuty od půlnoci (po 30 minutách).
    @Published var pickupMinutes: Int
    /// Objednané položky (jahody i ostatní produkty).
    @Published var extraItems: [OrderItem] = []
    @Published var note = ""

    /// Sloty po 30 minutách 7:00–19:30.
    static let timeSlots: [Int] = Array(stride(from: 7 * 60, through: 19 * 60 + 30, by: 30))

    init() {
        pickupDay = Calendar.current.startOfDay(for: Date())
        pickupMinutes = Self.defaultPickupMinutes()
    }

    /// Výchozí čas vyzvednutí = aktuální čas zařízení zaokrouhlený na nejbližší
    /// 30minutový slot, omezený na rozsah 7:00–19:30. `nonisolated` — čistá
    /// funkce bez stavu, volatelná i z defaultní hodnoty struktury.
    nonisolated static func defaultPickupMinutes(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let rounded = Int((Double(minutes) / 30).rounded()) * 30
        return min(max(rounded, 7 * 60), 19 * 60 + 30)
    }

    var pickupAt: Date {
        Calendar.current.date(byAdding: .minute, value: pickupMinutes, to: pickupDay) ?? pickupDay
    }

    var trimmedName: String {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Jméno + aspoň jedna položka.
    var canSave: Bool {
        !trimmedName.isEmpty && !items.isEmpty
    }

    // MARK: - Položky

    /// Platné položky (kladné množství, neprázdný název).
    var items: [OrderItem] {
        extraItems.filter {
            $0.quantity > 0 && !$0.productName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Celková cena rozpracované objednávky (Kč) — 0, pokud ceny nejsou nastavené.
    var total: Double {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    func addExtraItem(product: Product) {
        let step = product.quantityStep
        if let index = extraItems.firstIndex(where: { $0.productName == product.name }) {
            extraItems[index].quantity += step
        } else {
            extraItems.append(OrderItem(
                productName: product.name,
                quantity: step,
                unit: product.unit.rawValue,
                size: product.size,
                unitPrice: product.price
            ))
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

        extraItems = order.items
    }

    /// Nová objednávka z formuláře.
    func buildOrder(createdBy email: String) -> Order {
        Order(
            customerName: trimmedName,
            phone: normalizedPhone,
            items: items,
            pickupAt: pickupAt,
            note: normalizedNote,
            status: .aktivni,
            createdBy: email,
            updatedBy: email,
            calendarSyncStatus: .pending
        )
    }

    /// Propíše formulář do existující objednávky (Detail → Uložit změny).
    func apply(to order: Order) -> Order {
        var updated = order
        updated.customerName = trimmedName
        updated.phone = normalizedPhone
        updated.items = items
        updated.pickupAt = pickupAt
        updated.note = normalizedNote
        return updated
    }

    func reset() {
        customerName = ""
        phone = ""
        pickupDay = Calendar.current.startOfDay(for: Date())
        pickupMinutes = Self.defaultPickupMinutes()
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
