import XCTest
@testable import Jahody

final class DailySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }

    private func makeOrder(
        day: Int,
        hour: Int,
        kg: Double,
        status: OrderStatus = .aktivni,
        extraItems: [OrderItem] = []
    ) -> Order {
        var items = extraItems
        if kg > 0 {
            items.insert(OrderItem(productName: "Jahody", quantity: kg, unit: "kg"), at: 0)
        }
        return Order(
            customerName: "Test",
            items: items,
            pickupAt: date(day: day, hour: hour),
            status: status,
            createdBy: "test@example.com"
        )
    }

    // MARK: Součet kg jahod

    func testStrawberryKgSumsActiveOrders() {
        let orders = [
            makeOrder(day: 20, hour: 9, kg: 2),
            makeOrder(day: 20, hour: 15, kg: 0.5),
            makeOrder(day: 20, hour: 17, kg: 3),
        ]
        XCTAssertEqual(DailySummary.strawberryKg(orders), 5.5, accuracy: 0.0001)
    }

    func testCancelledOrdersAreExcludedFromTotals() {
        let orders = [
            makeOrder(day: 20, hour: 9, kg: 2),
            makeOrder(day: 20, hour: 10, kg: 4, status: .zrusena),
        ]
        XCTAssertEqual(DailySummary.strawberryKg(orders), 2, accuracy: 0.0001)
    }

    func testNonKgOrNonStrawberryItemsDoNotCountIntoKg() {
        let orders = [
            makeOrder(day: 20, hour: 9, kg: 1, extraItems: [
                OrderItem(productName: "Sýr", quantity: 2, unit: "kg"),
                OrderItem(productName: "Vajíčka", quantity: 10, unit: "ks"),
            ]),
        ]
        XCTAssertEqual(DailySummary.strawberryKg(orders), 1, accuracy: 0.0001)
    }

    // MARK: Seskupení po dnech

    func testGroupByDaySplitsAndSortsByDayAndTime() {
        let orders = [
            makeOrder(day: 21, hour: 10, kg: 1),
            makeOrder(day: 20, hour: 17, kg: 2),
            makeOrder(day: 20, hour: 9, kg: 3),
        ]
        let groups = DailySummary.groupByDay(orders, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].day, calendar.startOfDay(for: date(day: 20, hour: 0)))
        XCTAssertEqual(groups[0].orders.map(\.strawberryKg), [3, 2]) // 9:00 před 17:00
        XCTAssertEqual(groups[0].strawberryKg, 5, accuracy: 0.0001)
        XCTAssertEqual(groups[1].strawberryKg, 1, accuracy: 0.0001)
    }

    // MARK: Součty ostatních položek

    func testOtherItemTotalsAggregateByNameAndUnit() {
        let orders = [
            makeOrder(day: 20, hour: 9, kg: 1, extraItems: [
                OrderItem(productName: "Vajíčka", quantity: 10, unit: "ks"),
            ]),
            makeOrder(day: 20, hour: 11, kg: 0, extraItems: [
                OrderItem(productName: "Vajíčka", quantity: 20, unit: "ks"),
                OrderItem(productName: "Sirup", quantity: 2, unit: "ks"),
            ]),
        ]
        let totals = DailySummary.otherItemTotals(orders)

        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[0].name, "Vajíčka")
        XCTAssertEqual(totals[0].quantity, 30, accuracy: 0.0001)
        XCTAssertEqual(totals[1].name, "Sirup")
        XCTAssertEqual(totals[1].quantity, 2, accuracy: 0.0001)
    }
}
