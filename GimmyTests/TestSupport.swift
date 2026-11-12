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

/// A Rotinas row (columns A–L): routine, order, exercise, series, reps, notes, rest target, types, start, end.
func planRow(
    _ routine: String, order: Double?, _ exercise: String, sets: Double? = nil, reps: String = "",
    rest: Double? = nil, notes: String = "", kinds: String = "", start: Cell = .empty, end: Cell = .empty
) -> [Cell] {
    [.text(routine), order.map { .number($0) } ?? .empty, exercise.isEmpty ? .empty : .text(exercise), .empty, .empty,
     sets.map { .number($0) } ?? .empty, reps.isEmpty ? .empty : .text(reps), notes.isEmpty ? .empty : .text(notes),
     rest.map { .number($0) } ?? .empty, kinds.isEmpty ? .empty : .text(kinds), start, end]
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
