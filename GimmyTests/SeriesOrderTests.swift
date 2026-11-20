@testable import Gimmy
import XCTest

final class SeriesOrderTests: XCTestCase {
    /// One exercise's sets in a workout, as the ledger numbers them.
    private func exercise(_ kinds: [String], loads: [Double] = []) -> [SetRow] {
        makeLedger(registro: kinds.enumerated().map { i, kind in
            registroRow("20/11/2026", "Costas", "Row", kind: kind, load: i < loads.count ? loads[i] : Double(10 * (i + 1)), reps: 10)
        }).rows
    }

    private let mixed = ["", SetKind.drop, "", SetKind.restPause, SetKind.restPause, "", ""]

    func testSeriesKeepTheirPartsTogether() {
        let rows = exercise(mixed)
        XCTAssertEqual(rows.map(\.serie), ["1", "2", "2.1", "3", "3.1", "3.2", "4"])
        XCTAssertEqual(SeriesOrder.blocks(rows), [[0], [1, 2], [3, 4, 5], [6]])
        XCTAssertEqual(SeriesOrder.block(of: rows[4].row, in: rows), 2, "a part belongs to its set's series")
        XCTAssertNil(SeriesOrder.block(of: 999, in: rows))
    }

    func testMovingASeriesKeepsTheOthersInOrder() {
        let rows = exercise(mixed)
        XCTAssertEqual(SeriesOrder.move(rows, series: 0, to: 2), [1, 2, 3, 4, 5, 0, 6])
        XCTAssertEqual(SeriesOrder.move(rows, series: 3, to: 0), [6, 0, 1, 2, 3, 4, 5])
        XCTAssertEqual(SeriesOrder.move(rows, series: 1, to: 3), [0, 3, 4, 5, 6, 1, 2], "the drop moves with its part")
        XCTAssertNil(SeriesOrder.move(rows, series: 1, to: 1))
        XCTAssertNil(SeriesOrder.move(rows, series: 0, to: 9))
    }

    func testASeriesEndingInADropWithoutItsPartStaysLast() {
        let rows = exercise(["", "", SetKind.drop])
        XCTAssertNil(SeriesOrder.move(rows, series: 2, to: 0), "the next set would read as the drop's continuation")
        XCTAssertNil(SeriesOrder.move(rows, series: 0, to: 2))
        XCTAssertEqual(SeriesOrder.move(rows, series: 1, to: 0), [1, 0, 2])
    }

    func testMovedContentNumbersAsExpected() {
        let kinds = ["", SetKind.drop, "", ""]
        let loads: [Double] = [20, 50, 40, 30]
        let rows = exercise(kinds, loads: loads)
        XCTAssertEqual(rows.map(\.serie), ["1", "2", "2.1", "3"])
        guard let order = SeriesOrder.move(rows, series: 1, to: 0) else { return XCTFail("move refused") }
        XCTAssertEqual(order, [1, 2, 0, 3])
        let after = makeLedger(registro: order.map { i in
            registroRow("20/11/2026", "Costas", "Row", kind: kinds[i], load: loads[i], reps: 10)
        }).rows
        XCTAssertEqual(after.map(\.serie), ["1", "1.1", "2", "3"])
        XCTAssertEqual(after.map(\.load), [50, 40, 20, 30])
    }

    func testRowCheckAndContentCopy() {
        let x = SetRow(row: 5, kind: SetKind.drop, load: 42.5, reps: 8, day: "2026-11-20", routine: "Costas", exercise: "Row")
        var cells = [Cell](repeating: .empty, count: 13)
        cells[0] = .text("Drop")
        cells[1] = .number(42.5)
        cells[2] = .number(8)
        cells[3] = .text("1/2 até a falha")
        cells[9] = .number(Double(DayKey.serial("2026-11-20")))
        cells[10] = .text("Costas")
        cells[11] = .text("Row")
        cells[12] = .number(23.0 / 86400)
        XCTAssertTrue(RegistroRow.matches(cells, x))
        var changed = cells
        changed[1] = .number(40)
        XCTAssertFalse(RegistroRow.matches(changed, x))

        let content = RegistroRow.content(cells)
        XCTAssertEqual(content.dToG, [.text("Drop"), .number(42.5), .number(8), .literal("1/2 até a falha")],
                       "notes stay text, not a date")
        XCTAssertEqual(content.rest, .number(23.0 / 86400))
        XCTAssertEqual(RegistroRow.content([]).dToG, [.blank, .blank, .blank, .blank])
    }

    func testDragPayload() {
        XCTAssertEqual(SeriesOrder.row(fromPayload: SeriesOrder.dragPayload(row: 214)), 214)
        XCTAssertNil(SeriesOrder.row(fromPayload: "214"))
        XCTAssertNil(SeriesOrder.row(fromPayload: "gimmy-series:abc"))
    }
}
