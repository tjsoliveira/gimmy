@testable import Gimmy
import XCTest

final class DraftsTests: XCTestCase {
    private func row(_ n: Int, exercise: String = "Row") -> SetRow {
        SetRow(row: n, kind: "", load: nil, reps: 10, day: "2026-11-10", routine: "Costas", exercise: exercise)
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
        XCTAssertEqual(RestPause.parts([(40, 4), (40, 3)]).map(\.kind), [SetKind.restPause, ""])
        XCTAssertEqual(RestPause.parts([(40, 4)]).map(\.kind), [""])
        XCTAssertTrue(RestPause.parts([]).isEmpty)
        XCTAssertEqual(RestPause.suggestedReps(after: 8), 3)
        XCTAssertEqual(RestPause.suggestedReps(after: 1), 1)
    }

    func testRestPauseWrittenInOneSaveNumbersAsOneSeries() {
        let parts = RestPause.parts([(40, 4), (40, 3)])
        let rows = [registroRow("10/11/2026", "Costas", "Row", load: 40, reps: 10),
                    registroRow("10/11/2026", "Costas", "Row", kind: SetKind.restPause, load: 40, reps: 8)]
            + parts.map { registroRow("10/11/2026", "Costas", "Row", kind: $0.kind, load: $0.load, reps: $0.reps) }
            + [registroRow("10/11/2026", "Costas", "Row", load: 40, reps: 10)]
        let l = makeLedger(registro: rows)
        XCTAssertEqual(l.rows.map(\.serie), ["1", "2", "2.1", "2.2", "3"])
    }
}
