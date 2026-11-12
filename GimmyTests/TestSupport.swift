@testable import Gimmy
import Foundation

/// A Registro row (columns A–Q) as the Sheets API returns it with UNFORMATTED_VALUE.
func registroRow(
    _ day: String, _ routine: String, _ exercise: String,
    kind: String = "", load: Double? = nil, reps: Int? = 10,
    restSeconds: Double? = nil, durationMinutes: Double? = nil
) -> [Cell] {
    var r = [Cell](repeating: .empty, count: 17)
    r[3] = kind.isEmpty ? .empty : .text(kind)
    r[4] = load.map { .number($0) } ?? .empty
    r[5] = reps.map { .number(Double($0)) } ?? .empty
    r[12] = .text(day)
    r[13] = .text(routine)
    r[14] = .text(exercise)
    r[15] = restSeconds.map { .number($0 / 86400) } ?? .empty
    r[16] = durationMinutes.map { .number($0 / 1440) } ?? .empty
    return r
}

/// A Rotinas row: routine, order, exercise, sets, reps text, rest target.
func planRow(_ routine: String, order: Double, _ exercise: String, sets: Double?, reps: String, rest: Double? = nil) -> [Cell] {
    [.text(routine), .number(order), .text(exercise), .empty, .empty,
     sets.map { .number($0) } ?? .empty, .text(reps), .empty, rest.map { .number($0) } ?? .empty]
}

func makeLedger(registro: [[Cell]], plan: [[Cell]] = [], exercises: [[Cell]] = []) -> Ledger {
    var l = Ledger()
    l.parsePlan([[]] + plan)
    l.parseExercises([[]] + exercises)
    l.parseRegistro([[]] + registro)
    return l
}

func draft(for row: SetRow, load: String = "", reps: String = "10") -> SetDraft {
    SetDraft(row: row, last: nil, load: load, reps: reps, kind: row.kind, unit: .kg, step: 2.5, rest: "")
}
