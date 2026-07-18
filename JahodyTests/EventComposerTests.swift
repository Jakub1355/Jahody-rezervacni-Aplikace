import XCTest
@testable import Jahody

final class EventComposerTests: XCTestCase {
    private func makeOrder(
        name: String = "Jana Nováková",
        items: [OrderItem],
        note: String? = nil,
        phone: String? = nil,
        createdBy: String = "marie@example.com"
    ) -> Order {
        Order(
            customerName: name,
            phone: phone,
            items: items,
            pickupAt: Date(timeIntervalSince1970: 1_750_000_000),
            note: note,
            createdBy: createdBy
        )
    }

    // MARK: Název události

    func testTitleOnlyStrawberries() {
        let order = makeOrder(items: [
            OrderItem(productName: "Jahody", quantity: 3, unit: "kg"),
        ])
        XCTAssertEqual(EventComposer.title(for: order), "Jana Nováková – 3 kg jahod")
    }

    func testTitleWithDecimalQuantityUsesCzechComma() {
        let order = makeOrder(items: [
            OrderItem(productName: "Jahody", quantity: 0.5, unit: "kg"),
        ])
        XCTAssertEqual(EventComposer.title(for: order), "Jana Nováková – 0,5 kg jahod")
    }

    func testTitleWithExtraItemsAppendsNamesOnly() {
        let order = makeOrder(items: [
            OrderItem(productName: "Jahody", quantity: 3, unit: "kg"),
            OrderItem(productName: "Vejce", quantity: 10, unit: "ks"),
            OrderItem(productName: "Sirup", quantity: 2, unit: "ks"),
        ])
        XCTAssertEqual(
            EventComposer.title(for: order),
            "Jana Nováková – 3 kg jahod +vejce, sirup"
        )
    }

    func testTitleWithoutStrawberries() {
        let order = makeOrder(items: [
            OrderItem(productName: "Sýr", quantity: 1, unit: "ks"),
        ])
        XCTAssertEqual(EventComposer.title(for: order), "Jana Nováková – sýr")
    }

    // MARK: Popis události

    func testDescriptionContainsItemsNotePhoneAndAuthor() {
        let order = makeOrder(
            items: [
                OrderItem(productName: "Jahody", quantity: 2.5, unit: "kg"),
                OrderItem(productName: "Marmeláda", quantity: 1, unit: "ks"),
            ],
            note: "Přijede později",
            phone: "+420 777 123 456"
        )
        let description = EventComposer.description(for: order)
        XCTAssertTrue(description.contains("• Jahody: 2,5 kg"))
        XCTAssertTrue(description.contains("• Marmeláda: 1 ks"))
        XCTAssertTrue(description.contains("Poznámka: Přijede později"))
        XCTAssertTrue(description.contains("Telefon: +420 777 123 456"))
        XCTAssertTrue(description.contains("Zadal(a): marie@example.com"))
    }

    func testDescriptionOmitsEmptyNoteAndPhone() {
        let order = makeOrder(items: [
            OrderItem(productName: "Jahody", quantity: 1, unit: "kg"),
        ])
        let description = EventComposer.description(for: order)
        XCTAssertFalse(description.contains("Poznámka"))
        XCTAssertFalse(description.contains("Telefon"))
    }

    // MARK: Konec události

    func testEventEndsFifteenMinutesAfterPickup() {
        let order = makeOrder(items: [OrderItem(productName: "Jahody", quantity: 1, unit: "kg")])
        XCTAssertEqual(
            EventComposer.endDate(for: order).timeIntervalSince(order.pickupAt),
            15 * 60
        )
    }
}
