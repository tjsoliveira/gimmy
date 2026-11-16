@testable import Gimmy
import XCTest

final class FocusTests: XCTestCase {
    /// Two exercises of today's workout; `done` lists the rows already logged.
    private func workout(done: Set<Int>) -> (rows: [SetRow], groups: [ExerciseGroup]) {
        let rows = (2...5).map { n in
            SetRow(row: n, kind: "", load: done.contains(n) ? 10 : nil, reps: 10,
                   day: "2026-11-12", routine: "Ombro", exercise: n < 4 ? "A" : "B")
        }
        return (rows, Ledger().groups(rows))
    }

    func testOpensTheFirstExerciseWithSetsLeft() {
        let w = workout(done: [2, 3])
        XCTAssertEqual(Focus.group(w.groups, focusedRow: nil)?.exercise, "B")
        XCTAssertEqual(Focus.group(w.groups, focusedRow: 2)?.exercise, "A", "an exercise the user opened stays open")
    }

    func testCollapsingClosesEveryExerciseUntilOneIsOpened() {
        let w = workout(done: [2])
        XCTAssertNil(Focus.group(w.groups, focusedRow: nil, collapsed: true), "even with sets left, none opens by itself")
        XCTAssertNil(Focus.group(w.groups, focusedRow: 4, collapsed: true))
        XCTAssertEqual(Focus.group(w.groups, focusedRow: 4, collapsed: false)?.exercise, "B")
    }

    func testFinishingAnExerciseMovesToTheNextOne() {
        let w = workout(done: [2, 3])
        XCTAssertEqual(Focus.after(3, rows: w.rows, groups: w.groups, current: 3), 4)
        let partial = workout(done: [2])
        XCTAssertEqual(Focus.after(2, rows: partial.rows, groups: partial.groups, current: 2), 2,
                       "stays while the exercise has sets left")
    }

    func testTheLastExerciseClosesWithItsCheckLikeTheOthers() {
        let w = workout(done: [2, 3, 4, 5])
        XCTAssertNil(Focus.after(5, rows: w.rows, groups: w.groups, current: 5))
        XCTAssertNil(Focus.group(w.groups, focusedRow: nil), "nothing left to log: every exercise shows closed")
    }

    func testSavingTheLastSetOfAnEarlierExerciseOpensWhatIsLeft() {
        let w = workout(done: [3, 4, 5])
        XCTAssertEqual(Focus.after(5, rows: w.rows, groups: w.groups, current: 5), 2, "goes back to the set still open")
    }
}
