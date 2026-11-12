@testable import Gimmy
import XCTest

final class EvolutionTests: XCTestCase {
    private let ledger = makeLedger(
        registro: [
            registroRow("03/11/2026", "Costas", "Row", load: 40, durationMinutes: 50),
            registroRow("03/11/2026", "Costas", "Pulldown", load: 50),
            registroRow("10/11/2026", "Costas", "Row", kind: SetKind.warmup, load: 20),
            registroRow("10/11/2026", "Costas", "Row", load: 45),
            registroRow("10/11/2026", "Costas", "Extra", load: 10),
        ],
        plan: [planRow("Costas", order: 2, "Pulldown", sets: 3, reps: "10"),
               planRow("Costas", order: 1, "Row", sets: 3, reps: "10")]
    )

    func testRoutineSeriesPerSession() {
        let volume = ledger.routineSeries("Costas", metric: .volume, since: nil)
        XCTAssertEqual(volume.map(\.day), ["2026-11-03", "2026-11-10"])
        XCTAssertEqual(volume.map(\.value), [900, 550])
        let duration = ledger.routineSeries("Costas", metric: .duration, since: nil)
        XCTAssertEqual(duration.map(\.value), [50], "sessions without a duration are skipped")
        XCTAssertEqual(ledger.routineSeries("Costas", metric: .volume, since: "2026-11-05").count, 1)
    }

    func testExerciseSeriesIgnoresWarmups() {
        let oneRM = ledger.exerciseSeries("Row", metric: .oneRM, since: nil)
        XCTAssertEqual(oneRM.map(\.day), ["2026-11-03", "2026-11-10"])
        XCTAssertEqual(oneRM[1].value, 60.0, accuracy: 0.001)
        XCTAssertEqual(ledger.exerciseSeries("Row", metric: .topLoad, since: nil).map(\.value), [40, 45])
    }

    func testExercisesOfRoutineFollowThePlanThenExtras() {
        XCTAssertEqual(ledger.exercises(inRoutine: "Costas"), ["Row", "Pulldown", "Extra"])
        XCTAssertEqual(ledger.loggedExercises(), ["Extra", "Pulldown", "Row"])
    }
}
