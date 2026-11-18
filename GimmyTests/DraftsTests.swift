@testable import Gimmy
import XCTest

final class DraftsTests: XCTestCase {
    private func row(_ n: Int, exercise: String = "Row") -> SetRow {
        SetRow(row: n, kind: "", load: nil, reps: 10, day: "2026-11-10", routine: "Costas", exercise: exercise)
    }

    func testPauseGoesOnTheSetAndEveryPartButTheLast() {
        XCTAssertEqual(ChainParts.pauseRows(after: 10, parts: 2), [10, 11], "row 12, the last part, keeps the clock's rest")
        XCTAssertEqual(ChainParts.pauseRows(after: 10, parts: 1), [10])
        XCTAssertEqual(ChainParts.pauseRows(after: 10, parts: 0), [])
    }

    func testChangingThePauseCountsAsAnEdit() {
        let base = draft(for: row(5))
        var edited = base
        edited.pause = "0:10"
        XCTAssertTrue(edited.differs(from: base))
    }

    func testUnsavedDraftIsKeptPerSet() {
        var store = DraftStore()
        store.stash(draft(for: row(5), load: "40"))
        XCTAssertEqual(store.draft(for: row(5))?.load, "40")
        XCTAssertNil(store.draft(for: row(5, exercise: "Other")), "a different set on that row doesn't get the draft")
        XCTAssertNil(store.draft(for: row(6)))
        store.remove(5)
        XCTAssertNil(store.draft(for: row(5)))
    }

    func testDraftsFollowInsertedAndDeletedRows() {
        var store = DraftStore()
        store.stash(draft(for: row(3), load: "30"))
        store.stash(draft(for: row(5), load: "50"))
        store.shift(after: 4, by: 2)
        XCTAssertEqual(store.draft(for: row(3))?.load, "30", "rows above the insert stay")
        XCTAssertEqual(store.draft(for: row(7))?.load, "50")
        XCTAssertEqual(store.draft(for: row(7))?.row.row, 7)
        XCTAssertNil(store.draft(for: row(5)))

        store.removeAndShift(3)
        XCTAssertNil(store.draft(for: row(3)))
        XCTAssertEqual(store.draft(for: row(6))?.load, "50")
    }

    func testDraftDiffersOnlyWhenSomethingChanged() {
        let base = draft(for: row(5), load: "40")
        XCTAssertFalse(base.differs(from: base))
        var changed = base
        changed.reps = "8"
        XCTAssertTrue(changed.differs(from: base))
        var withPart = base
        withPart.minis = [MiniSet(load: "40", reps: "3")]
        XCTAssertTrue(withPart.differs(from: base))
    }

    func testRestPausePartsEndTheChain() {
        XCTAssertEqual(ChainParts.parts([(40, 4), (40, 3)], kind: SetKind.restPause).map(\.kind), [SetKind.restPause, ""])
        XCTAssertEqual(ChainParts.parts([(40, 4)], kind: SetKind.restPause).map(\.kind), [""])
        XCTAssertTrue(ChainParts.parts([], kind: SetKind.restPause).isEmpty)
        XCTAssertEqual(ChainParts.suggestedReps(after: 8), 3)
        XCTAssertEqual(ChainParts.suggestedReps(after: 1), 1)
    }

    func testDropPartsEndTheChain() {
        let parts = ChainParts.parts([(30, 8), (22.5, 8)], kind: SetKind.drop)
        XCTAssertEqual(parts.map(\.kind), [SetKind.drop, ""], "the drops continue the series, the last one closes it")
        XCTAssertEqual(parts.map(\.load), [30, 22.5])
        XCTAssertEqual(ChainParts.defaultPause(SetKind.drop), 10)
        XCTAssertEqual(ChainParts.defaultPause(SetKind.restPause), 15)
    }

    func testDropLoadTakesAboutAFifthOffOnTheUnitStep() {
        XCTAssertEqual(ChainParts.dropLoad(after: 60, unit: .kg), 47.5)
        XCTAssertEqual(ChainParts.dropLoad(after: 25, unit: .kg), 20)
        XCTAssertEqual(ChainParts.dropLoad(after: 10, unit: .kg), 8, "light loads step by 1 kg")
        XCTAssertEqual(ChainParts.dropLoad(after: 45, unit: .lb), 35)
        XCTAssertEqual(ChainParts.dropLoad(after: 0, unit: .kg), 0)
    }

    func testNewPartStartsFromTheOneBefore() {
        let drop = ChainParts.nextPart(kind: SetKind.drop, load: 50, reps: 8, first: true, unit: .kg)
        XCTAssertEqual(drop.load, 40)
        XCTAssertEqual(drop.reps, 8)
        let restPause = ChainParts.nextPart(kind: SetKind.restPause, load: 50, reps: 9, first: true, unit: .kg)
        XCTAssertEqual(restPause.load, 50)
        XCTAssertEqual(restPause.reps, 3)
        XCTAssertEqual(ChainParts.nextPart(kind: SetKind.restPause, load: 50, reps: 3, first: false, unit: .kg).reps, 3)
        XCTAssertNil(ChainParts.nextPart(kind: SetKind.drop, load: nil, reps: 8, first: true, unit: .kg).load,
                     "no load typed yet: the drop's load stays empty")
    }

    func testDropWrittenInOneSaveNumbersAsOneSeries() {
        let parts = ChainParts.parts([(40, 8), (30, 6)], kind: SetKind.drop)
        let rows = [registroRow("10/11/2026", "Costas", "Row", load: 50, reps: 10),
                    registroRow("10/11/2026", "Costas", "Row", kind: SetKind.drop, load: 50, reps: 8)]
            + parts.map { registroRow("10/11/2026", "Costas", "Row", kind: $0.kind, load: $0.load, reps: $0.reps) }
            + [registroRow("10/11/2026", "Costas", "Row", load: 50, reps: 10)]
        XCTAssertEqual(makeLedger(registro: rows).rows.map(\.serie), ["1", "2", "2.1", "2.2", "3"])
    }

    func testRestPauseWrittenInOneSaveNumbersAsOneSeries() {
        let parts = ChainParts.parts([(40, 4), (40, 3)], kind: SetKind.restPause)
        let rows = [registroRow("10/11/2026", "Costas", "Row", load: 40, reps: 10),
                    registroRow("10/11/2026", "Costas", "Row", kind: SetKind.restPause, load: 40, reps: 8)]
            + parts.map { registroRow("10/11/2026", "Costas", "Row", kind: $0.kind, load: $0.load, reps: $0.reps) }
            + [registroRow("10/11/2026", "Costas", "Row", load: 40, reps: 10)]
        let l = makeLedger(registro: rows)
        XCTAssertEqual(l.rows.map(\.serie), ["1", "2", "2.1", "2.2", "3"])
    }
}
