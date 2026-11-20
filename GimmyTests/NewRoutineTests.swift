@testable import Gimmy
import XCTest

final class NewRoutineTests: XCTestCase {
    private func row(_ n: Int, _ exercise: String, _ kind: String = "", reps: Int? = 10, load: Double? = 40) -> SetRow {
        SetRow(row: n, kind: kind, load: load, reps: reps, day: "2026-11-20", routine: "Costas", exercise: exercise)
    }

    private let template = Template(rows: [
        TemplateRow(exercise: "Row", kind: SetKind.warmup, reps: 15),
        TemplateRow(exercise: "Row", kind: "", reps: 12),
        TemplateRow(exercise: "Pulldown", kind: "", reps: 10),
    ])

    func testOnlyTheStructureCountsAsAChange() {
        let same = [row(2, "Row", SetKind.warmup, reps: 14, load: 20), row(3, "Row", reps: 9, load: 60), row(4, "Pulldown", load: nil)]
        XCTAssertFalse(NewRoutine.changed(session: same, template: template), "loads and reps done don't count")

        XCTAssertTrue(NewRoutine.changed(session: [row(2, "Row", SetKind.warmup), row(3, "Row", SetKind.failure), row(4, "Pulldown")],
                                         template: template), "a set's type changed")
        XCTAssertTrue(NewRoutine.changed(session: same + [row(5, "Pulldown")], template: template), "a set was added")
        XCTAssertTrue(NewRoutine.changed(session: [row(2, "Pulldown"), row(3, "Row", SetKind.warmup), row(4, "Row")],
                                         template: template), "the exercises changed order")
        XCTAssertTrue(NewRoutine.changed(session: same + [row(5, "Calf")], template: template), "an exercise was added")
    }

    func testTheRoutineKeepsTargetsWhereASetWasAlready() {
        let plan = ["Row": NewRoutine.Planned(sets: [PlanSet(kind: SetKind.warmup, reps: 15), PlanSet(kind: "", reps: 12),
                                                     PlanSet(kind: "", reps: 10)],
                                              notes: "1ª de aquecimento", rest: 120)]
        let session = [
            row(2, "Row", SetKind.warmup, reps: 14),
            row(3, "Row", SetKind.drop, reps: 11),
            row(4, "Row", reps: 7),
            row(5, "Row", reps: 9),
            row(6, "Calf", reps: 15, load: nil),
        ]
        let items = NewRoutine.items(session: session, plan: plan)
        XCTAssertEqual(items.map(\.exercise), ["Row", "Calf"])
        XCTAssertEqual(items[0].sets, [PlanSet(kind: SetKind.warmup, reps: 15), PlanSet(kind: SetKind.drop, reps: 12),
                                       PlanSet(kind: "", reps: 7), PlanSet(kind: "", reps: 10)],
                       "1, 2 and 3 keep their targets; the drop's part (2.1) is new and takes today's reps")
        XCTAssertEqual(items[0].notes, "1ª de aquecimento")
        XCTAssertEqual(items[0].rest, 120)
        XCTAssertEqual(items[1], NewRoutine.Item(exercise: "Calf", sets: [PlanSet(kind: "", reps: 15)], notes: "", rest: nil),
                       "an exercise added today comes in with its sets, done or not")
    }

    func testAnExerciseSplitInTwoComesTogether() {
        let items = NewRoutine.items(session: [row(2, "Row"), row(3, "Pulldown"), row(4, "Row", reps: 8)], plan: [:])
        XCTAssertEqual(items.map(\.exercise), ["Row", "Pulldown"])
        XCTAssertEqual(items[0].sets.map(\.reps), [10, 8])
    }

    func testDayOffset() {
        XCTAssertEqual(DayKey.offset("2026-11-30", by: 1), "2026-12-01")
        XCTAssertEqual(DayKey.offset("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(DayKey.offset("2026-03-01", by: -1), "2026-02-28")
    }
}
