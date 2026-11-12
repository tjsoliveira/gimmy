@testable import Gimmy
import XCTest

/// The screenshot data must keep showing what the README promises.
final class DemoDataTests: XCTestCase {
    func testSampleDataFillsEveryScreen() {
        let tabs = DemoData.make()
        var l = Ledger()
        l.parsePlan(tabs.plan)
        l.parseExercises(tabs.exercises)
        l.parseRegistro(tabs.registro)
        let today = DayKey.from(Date())

        XCTAssertEqual(l.routines(on: today), ["Costas", "Peito", "Pernas", "Ombro"])
        XCTAssertEqual(l.versions.map { $0.status(today: today) }.filter { $0 == .ended }.count, 1)
        XCTAssertEqual(l.versions.map { $0.status(today: today) }.filter { $0 == .upcoming }.count, 1)

        let rows = l.sessionRows(day: today, routine: "Costas")
        XCTAssertTrue(rows.contains(where: \.isDone))
        XCTAssertTrue(rows.contains(where: { !$0.isDone }))
        let rest = tabs.restRow.flatMap { l.row($0) }
        XCTAssertEqual(rest?.isDone, true)
        XCTAssertNil(rest?.rest, "the running rest clock belongs to a set without a saved rest")
        XCTAssertGreaterThanOrEqual(l.sessions().count, 10)

        guard let costas = l.version(named: "Costas", on: today) else { return XCTFail("missing Costas") }
        XCTAssertTrue(l.items(of: costas).allSatisfy { l.plannedSets($0, before: today).source == .configured })
        XCTAssertNotNil(l.items(of: costas).first { $0.exercise == "Lat Pulldown (Machine)" })
    }
}
