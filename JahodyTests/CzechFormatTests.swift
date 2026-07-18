import XCTest
@testable import Jahody

final class CzechFormatTests: XCTestCase {
    func testQuantityFormatting() {
        XCTAssertEqual(CzechFormat.quantity(3), "3")
        XCTAssertEqual(CzechFormat.quantity(0.5), "0,5")
        XCTAssertEqual(CzechFormat.quantity(2.25), "2,25")
    }

    func testParseQuantityAcceptsCommaAndDot() {
        XCTAssertEqual(CzechFormat.parseQuantity("0,5"), 0.5)
        XCTAssertEqual(CzechFormat.parseQuantity("0.5"), 0.5)
        XCTAssertEqual(CzechFormat.parseQuantity("3"), 3)
        XCTAssertEqual(CzechFormat.parseQuantity(" 2,5 "), 2.5)
        XCTAssertNil(CzechFormat.parseQuantity(""))
        XCTAssertNil(CzechFormat.parseQuantity("abc"))
    }

    func testDayFormatterProducesCzechFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        // Poledne, aby výsledek nezávisel na časové zóně stroje, kde testy běží.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 12))!
        XCTAssertEqual(CzechFormat.dayFormatter.string(from: thursday), "čtvrtek 23. 7.")
    }

    func testItemsSummary() {
        let items = [
            OrderItem(productName: "Jahody", quantity: 3, unit: "kg"),
            OrderItem(productName: "Vajíčka", quantity: 10, unit: "ks"),
        ]
        XCTAssertEqual(CzechFormat.itemsSummary(items), "3 kg jahody · 10 ks vajíčka")
    }
}
