@testable import Gimmy
import XCTest

final class LedgerTests: XCTestCase {
    func testDropAndRestPauseContinueTheSeries() {
        let kinds = ["", SetKind.drop, "", SetKind.restPause, SetKind.restPause, ""]
        let l = makeLedger(registro: kinds.map { registroRow("03/11/2026", "Costas", "Row", kind: $0, load: 40) }
            + [registroRow("03/11/2026", "Costas", "Pulldown", load: 50)])
        XCTAssertEqual(l.rows.prefix(6).map(\.serie), ["1", "2", "2.1", "3", "3.1", "3.2"])
        XCTAssertEqual(l.rows[6].serie, "1", "each exercise numbers its own sets")
        XCTAssertTrue(l.hasContinuation(l.rows[3]))
        XCTAssertFalse(l.hasContinuation(l.rows[5]))
    }

    func testChainRestTargets() {
        XCTAssertEqual(SetKind.chainRest(SetKind.drop), 10)
        XCTAssertEqual(SetKind.chainRest(SetKind.restPause), 15)
        XCTAssertNil(SetKind.chainRest(""))
        XCTAssertTrue(SetKind.chains(SetKind.restPause))
        XCTAssertFalse(SetKind.chains(SetKind.failure))
    }

    private func twoSessions(today: [Double]) -> Ledger {
        makeLedger(registro: [
            registroRow("03/11/2026", "Costas", "Row", load: 40),
            registroRow("03/11/2026", "Costas", "Row", load: 40),
        ] + today.map { registroRow("10/11/2026", "Costas", "Row", load: $0) })
    }

    func testStatusAndRecord() {
        let up = twoSessions(today: [45, 40])
        let g = up.groups(up.sessionRows(day: "2026-11-10", routine: "Costas"))[0]
        XCTAssertEqual(up.status(g, day: "2026-11-10")?.kind, .up)
        XCTAssertEqual(up.status(g, day: "2026-11-10")?.value ?? 0, 6.7, accuracy: 0.001)
        XCTAssertTrue(up.isRecord(g, day: "2026-11-10"))

        let down = twoSessions(today: [35, 40])
        let gd = down.groups(down.sessionRows(day: "2026-11-10", routine: "Costas"))[0]
        XCTAssertEqual(down.status(gd, day: "2026-11-10")?.kind, .down)
        XCTAssertFalse(down.isRecord(gd, day: "2026-11-10"))

        let flat = twoSessions(today: [40, 40])
        let gf = flat.groups(flat.sessionRows(day: "2026-11-10", routine: "Costas"))[0]
        XCTAssertEqual(flat.status(gf, day: "2026-11-10")?.kind, .flat)

        let first = makeLedger(registro: [registroRow("03/11/2026", "Costas", "Row", load: 40)])
        let g1 = first.groups(first.sessionRows(day: "2026-11-03", routine: "Costas"))[0]
        XCTAssertEqual(first.status(g1, day: "2026-11-03")?.kind, .first)
    }

    func testWarmupsNeverCountAsRecordsOrVolume() {
        let l = makeLedger(registro: [
            registroRow("03/11/2026", "Costas", "Row", load: 40),
            registroRow("10/11/2026", "Costas", "Row", kind: SetKind.warmup, load: 100),
            registroRow("10/11/2026", "Costas", "Row", load: 40),
        ])
        XCTAssertEqual(l.best(l.sets(exercise: "Row", day: "2026-11-10")) ?? 0, 53.3, accuracy: 0.001)
        XCTAssertEqual(l.volume(routine: "Costas", day: "2026-11-10"), 400)
    }

    func testVolumeConvertsPoundsToKilograms() {
        let l = makeLedger(
            registro: [
                registroRow("03/11/2026", "Braços", "Curl", load: 100, reps: 10),
                registroRow("03/11/2026", "Braços", "Rosca", load: 40, reps: 10),
            ],
            exercises: [[.text("Curl"), .empty, .empty, .text("lb")], [.text("Rosca"), .empty, .empty, .text("kg")]]
        )
        XCTAssertEqual(l.unit(of: "Curl"), .lb)
        XCTAssertEqual(l.volume(routine: "Braços", day: "2026-11-03"), 1000 * WeightUnit.poundInKg + 400, accuracy: 0.001)
    }

    func testTemplateFromPlanWhenRoutineWasNeverDone() {
        let l = makeLedger(registro: [], plan: [
            planRow("Costas", order: 2, "B", sets: 2, reps: "12"),
            planRow("Costas", order: 1, "A", sets: 4, reps: "15-12-10-6", rest: 120),
        ])
        let t = l.template(routine: "Costas", day: "2026-11-10")
        XCTAssertNil(t.previousDay)
        XCTAssertEqual(t.rows.map(\.exercise), ["A", "A", "A", "A", "B", "B"])
        XCTAssertEqual(t.rows.map(\.reps), [15, 12, 10, 6, 12, 12])
        XCTAssertEqual(l.restTarget(exercise: "A", routine: "Costas"), 120)
        XCTAssertEqual(l.restTarget(exercise: "B", routine: "Costas"), 90)
    }

    func testTemplateCopiesThePreviousSession() {
        let l = makeLedger(registro: [
            registroRow("03/11/2026", "Costas", "A", load: 40, reps: 12),
            registroRow("03/11/2026", "Costas", "A", kind: SetKind.drop, load: 40, reps: 8),
            registroRow("03/11/2026", "Costas", "A", load: 30, reps: 6),
            registroRow("03/11/2026", "Costas", "B", load: nil, reps: 10),
        ])
        let t = l.template(routine: "Costas", day: "2026-11-10")
        XCTAssertEqual(t.previousDay, "2026-11-03")
        XCTAssertEqual(t.rows.map(\.exercise), ["A", "A", "A"], "only logged sets are copied")
        XCTAssertEqual(t.rows.map(\.kind), ["", SetKind.drop, ""])
        XCTAssertEqual(l.plannedExercises(t).map(\.sets), [2], "a drop part is not a new set")
    }

    func testSessionsAndStats() {
        let l = makeLedger(registro: [
            registroRow("03/11/2026", "Costas", "Row", load: 40, restSeconds: 90, durationMinutes: 50),
            registroRow("03/11/2026", "Costas", "Row", load: 40, restSeconds: 110),
            registroRow("10/11/2026", "Costas", "Row", load: 50),
            registroRow("10/11/2026", "Costas", "Row", load: nil),
        ])
        let sessions = l.sessions()
        XCTAssertEqual(sessions.map(\.day), ["2026-11-10", "2026-11-03"])
        let old = l.stats(sessions[1])
        XCTAssertEqual(old.duration, 50)
        XCTAssertEqual(old.averageRest ?? 0, 100, accuracy: 0.001)
        let recent = l.stats(sessions[0])
        XCTAssertEqual(recent.doneSeries, 1)
        XCTAssertEqual(recent.pending, 1)
        XCTAssertEqual(recent.volume, 500)
        XCTAssertEqual(recent.volumeChange ?? 0, 500.0 / 800 - 1, accuracy: 0.0001)
    }
}
