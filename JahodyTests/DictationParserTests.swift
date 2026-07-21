import XCTest
@testable import Jahody

final class DictationParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// Pevné „teď“ = středa 15. 7. 2026, 12:00, aby testy dnů byly deterministické.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!
    }

    private func parse(_ text: String) -> DictationResult {
        DictationParser.parse(text, products: Product.defaults, now: now, calendar: calendar)
    }

    private func minutes(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    // MARK: Kompletní věta

    func testFullSentence() {
        let result = parse("Jana Nováková, telefon 777 123 456, přijede zítra v pět, chce tři kila jahod")
        XCTAssertEqual(result.customerName, "Jana Nováková")
        XCTAssertEqual(result.phone?.filter(\.isNumber), "777123456")
        XCTAssertEqual(result.strawberryKg, 3)
        XCTAssertEqual(result.pickupMinutes, minutes(17, 0)) // „v pět“ = odpoledne
        XCTAssertEqual(
            result.pickupDay,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16))
        )
    }

    // MARK: Jméno

    func testNameStopsAtFirstNumberOrKeyword() {
        XCTAssertEqual(parse("Petr dvě kila").customerName, "Petr")
        XCTAssertEqual(parse("Marek zítra tři kila").customerName, "Marek")
        XCTAssertNil(parse("půl kila jahod zítra").customerName)
    }

    func testNameStripsFillerWords() {
        XCTAssertEqual(parse("objednávka pro Alenu, dvě kila").customerName, "Alenu")
    }

    // MARK: Telefon

    func testPhoneWithSpaces() {
        XCTAssertEqual(parse("Karel 606 707 808 dvě kila").phone?.filter(\.isNumber), "606707808")
    }

    func testPhoneWithPrefix() {
        let result = parse("Karel +420 606 707 808 dvě kila")
        XCTAssertEqual(result.phone?.filter(\.isNumber), "420606707808")
    }

    func testShortNumberIsNotPhone() {
        XCTAssertNil(parse("Karel tři kila").phone)
    }

    // MARK: Jahody (kg)

    func testStrawberryWordQuantity() {
        XCTAssertEqual(parse("tři kila jahod").strawberryKg, 3)
    }

    func testStrawberryHalfKilo() {
        XCTAssertEqual(parse("půl kila jahod").strawberryKg, 0.5)
    }

    func testStrawberryWholeAndHalf() {
        XCTAssertEqual(parse("dvě a půl kila jahod").strawberryKg, 2.5)
    }

    func testStrawberryDecimalDigits() {
        XCTAssertEqual(parse("1,5 kg jahod").strawberryKg, 1.5)
    }

    func testKilogramsOfOtherProductIsNotStrawberries() {
        // „dvě kila sýra“ nejsou jahody.
        let result = parse("Jana dvě kila sýra")
        XCTAssertNil(result.strawberryKg)
        XCTAssertTrue(result.extraItems.contains { $0.productName == "Sýr" && $0.quantity == 2 })
    }

    // MARK: Den

    func testRelativeDays() {
        XCTAssertEqual(parse("dnes").pickupDay, calendar.startOfDay(for: now))
        XCTAssertEqual(
            parse("zítra").pickupDay,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16))
        )
        XCTAssertEqual(
            parse("pozítří").pickupDay,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 17))
        )
    }

    func testWeekdayResolvesToNextOccurrence() {
        // Ze středy 15. 7. je nejbližší pátek 17. 7.
        XCTAssertEqual(
            parse("přijede v pátek").pickupDay,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 17))
        )
        // Nejbližší pondělí je 20. 7.
        XCTAssertEqual(
            parse("v pondělí").pickupDay,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))
        )
    }

    // MARK: Čas

    func testAfternoonHeuristicForBareHour() {
        XCTAssertEqual(parse("v pět").pickupMinutes, minutes(17, 0))
        XCTAssertEqual(parse("v šest").pickupMinutes, minutes(18, 0))
    }

    func testMorningHourStaysMorning() {
        XCTAssertEqual(parse("v deset dopoledne").pickupMinutes, minutes(10, 0))
        XCTAssertEqual(parse("v osm").pickupMinutes, minutes(8, 0))
    }

    func testHalfPast() {
        XCTAssertEqual(parse("o půl páté").pickupMinutes, minutes(16, 30))
    }

    func testClockAndBareHourWithMinutes() {
        XCTAssertEqual(parse("v 17:30").pickupMinutes, minutes(17, 30))
        XCTAssertEqual(parse("sedmnáct třicet").pickupMinutes, minutes(17, 30))
    }

    func testLargeKgIsNotMistakenForTime() {
        // „dvacet kila“ nesmí být 20:00.
        let result = parse("dvacet kila jahod zítra")
        XCTAssertEqual(result.strawberryKg, 20)
        XCTAssertNil(result.pickupMinutes)
    }

    // MARK: Další položky

    func testExtraItemsFromProducts() {
        let result = parse("Jana tři kila jahod a deset vajec zítra v pět")
        XCTAssertEqual(result.strawberryKg, 3)
        XCTAssertTrue(result.extraItems.contains { $0.productName == "Vajíčka" && $0.quantity == 10 })
    }

    func testNameDoesNotGrabProductWord() {
        // Po jménu následuje produkt „jahody“ — nesmí se dostat do jména.
        let result = parse("Jana Nováková jahody tři kila")
        XCTAssertEqual(result.customerName, "Jana Nováková")
        XCTAssertEqual(result.strawberryKg, 3)
    }

    func testProductBeforeQuantity() {
        // Produkt může být i před množstvím: „brambory tři kila“.
        let products = Product.defaults + [Product(id: "brambory", name: "Brambory", unit: .kg)]
        let result = DictationParser.parse("Jana brambory tři kila", products: products, now: now, calendar: calendar)
        XCTAssertEqual(result.customerName, "Jana")
        XCTAssertNil(result.strawberryKg)
        XCTAssertTrue(result.extraItems.contains { $0.productName == "Brambory" && $0.quantity == 3 })
    }

    // MARK: Neznámé produkty (mimo číselník)

    func testUnknownProductGoesToUnknownItems() {
        // „třešně“ nejsou ve výchozím číselníku → neznámá položka.
        let result = parse("Jana pět třešní")
        XCTAssertEqual(result.customerName, "Jana")
        XCTAssertTrue(result.extraItems.isEmpty)
        XCTAssertTrue(result.unknownItems.contains { $0.quantity == 5 })
    }

    func testKnownProductIsNotUnknown() {
        let result = parse("deset vajec")
        XCTAssertTrue(result.extraItems.contains { $0.productName == "Vajíčka" && $0.quantity == 10 })
        XCTAssertTrue(result.unknownItems.isEmpty)
    }

    func testStrawberriesAfterAnotherProduct() {
        // „pět sýrů tři kila jahod“ → jahody 3 kg i sýr 5 ks (jahody za markerem).
        let result = parse("pět sýrů tři kila jahod")
        XCTAssertEqual(result.strawberryKg, 3)
        XCTAssertTrue(result.extraItems.contains { $0.productName == "Sýr" && $0.quantity == 5 })
    }

    // MARK: Poznámka

    func testNoteAfterKeyword() {
        let result = parse("Jana dvě kila zítra poznámka zavolat před příjezdem")
        XCTAssertEqual(result.note, "zavolat před příjezdem")
        XCTAssertEqual(result.strawberryKg, 2)
    }

    // MARK: Přepis se vždy zachová

    func testTranscriptPreserved() {
        let text = "něco nerozpoznatelného"
        XCTAssertEqual(parse(text).transcript, text)
    }
}
