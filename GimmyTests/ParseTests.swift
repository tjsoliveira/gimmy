@testable import Gimmy
import XCTest

final class ParseTests: XCTestCase {
    func testNumbersAcceptBrazilianAndDotDecimals() {
        XCTAssertEqual(Parse.number("42,5"), 42.5)
        XCTAssertEqual(Parse.number("1.234,5"), 1234.5)
        XCTAssertEqual(Parse.number("42.5"), 42.5)
        XCTAssertEqual(Parse.number(.number(20)), 20)
        XCTAssertNil(Parse.number(""))
        XCTAssertNil(Parse.number("abc"))
    }

    func testDaysFromTextAndSerial() {
        XCTAssertEqual(Parse.day(.text("03/11/2026")), "2026-11-03")
        XCTAssertEqual(Parse.day(.text("2026-11-03")), "2026-11-03")
        let serial = DayKey.serial("2026-11-03")
        XCTAssertEqual(Parse.day(.number(Double(serial))), "2026-11-03")
        XCTAssertNil(Parse.day(.empty))
    }

    func testRestAndDurationColumns() {
        XCTAssertEqual(Parse.seconds(.text("1:30")), 90)
        XCTAssertEqual(Parse.seconds(.text("0:01:30")), 90)
        XCTAssertEqual(Parse.seconds(.number(90.0 / 86400)), 90)
        XCTAssertEqual(Parse.minutes(.text("0:51")), 51)
        XCTAssertEqual(Parse.minutes(.number(51.0 / 1440)), 51)
        XCTAssertNil(Parse.seconds(.empty))
    }

    func testRestTypedOnANumberPad() {
        XCTAssertEqual(RestInput.parse("130"), .seconds(90))
        XCTAssertEqual(RestInput.parse("90"), .seconds(90))
        XCTAssertEqual(RestInput.parse("45"), .seconds(45))
        XCTAssertEqual(RestInput.parse("1:30"), .seconds(90))
        XCTAssertEqual(RestInput.parse("1.30"), .seconds(90))
        XCTAssertEqual(RestInput.parse(""), .empty)
        XCTAssertEqual(RestInput.parse("175"), .invalid)
        XCTAssertEqual(RestInput.parse("1:75"), .invalid)
        XCTAssertEqual(RestInput.parse("abc"), .invalid)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.duration(90), "1:30")
        XCTAssertEqual(Fmt.minutes(51), "51 min")
        XCTAssertEqual(Fmt.minutes(65), "1h05")
        XCTAssertEqual(Fmt.n(42.5), "42,5")
        XCTAssertEqual(Fmt.loadInput(1234.5), "1234,5")
        XCTAssertEqual(Fmt.shortDay("2026-11-03"), "03/11")
    }

    func testOneRepMaxEstimate() {
        XCTAssertEqual(OneRM.estimate(100, 10)!, 133.3, accuracy: 0.001)
        XCTAssertEqual(OneRM.estimate(100, 12)!, 140.0, accuracy: 0.001)
        XCTAssertNil(OneRM.estimate(nil, 10))
        XCTAssertNil(OneRM.estimate(100, 0))
        XCTAssertNil(OneRM.estimate(100, 37))
    }
}
