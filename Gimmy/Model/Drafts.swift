import Foundation

/// One extra part of a rest-pause set, logged from the same editor.
struct MiniSet: Identifiable, Equatable {
    let id = UUID()
    var load: String
    var reps: String

    static func == (a: MiniSet, b: MiniSet) -> Bool { a.load == b.load && a.reps == b.reps }
}

/// What the set editor works on; saved only when the user taps Salvar.
struct SetDraft: Identifiable {
    var row: SetRow
    var last: SetRow?
    var load: String
    var reps: String
    var kind: String
    var unit: WeightUnit
    var step: Double
    var rest: String
    /// Drop or rest-pause parts after this set; written as new rows on save.
    var minis: [MiniSet] = []
    /// Pause between the drop or rest-pause parts ("0:10"), written on the set and every part but the last.
    var pause = ""
    var id: Int { row.row }

    /// True when the user typed or chose something different from what `other` holds.
    func differs(from other: SetDraft) -> Bool {
        load != other.load || reps != other.reps || kind != other.kind
            || unit != other.unit || rest != other.rest || minis != other.minis || pause != other.pause
    }
}

/// Unsaved editor contents, kept per set so closing the editor doesn't lose them.
/// Keyed by sheet row; inserting or deleting rows shifts the keys.
struct DraftStore {
    private(set) var drafts: [Int: SetDraft] = [:]

    /// The stashed draft for this set, if it still describes the same set.
    func draft(for row: SetRow) -> SetDraft? {
        guard let d = drafts[row.row],
              d.row.exercise == row.exercise, d.row.day == row.day, d.row.routine == row.routine else { return nil }
        return d
    }

    mutating func stash(_ draft: SetDraft) { drafts[draft.row.row] = draft }

    mutating func remove(_ row: Int) { drafts[row] = nil }

    /// Rows were inserted right after `after`: everything below moves down by `count`.
    mutating func shift(after: Int, by count: Int) {
        drafts = Dictionary(uniqueKeysWithValues: drafts.map { key, d in
            guard key > after else { return (key, d) }
            var moved = d
            moved.row.row += count
            return (key + count, moved)
        })
    }

    /// Sets moved to other rows (`old: new`), as when the series of an exercise are reordered:
    /// their drafts move with them.
    mutating func remap(_ moves: [Int: Int]) {
        var next = drafts.filter { moves[$0.key] == nil }
        for (old, new) in moves {
            guard var d = drafts[old] else { continue }
            d.row.row = new
            next[new] = d
        }
        drafts = next
    }

    /// Row `row` was deleted: its draft goes, everything below moves up by one.
    mutating func removeAndShift(_ row: Int) {
        drafts[row] = nil
        drafts = Dictionary(uniqueKeysWithValues: drafts.map { key, d in
            guard key > row else { return (key, d) }
            var moved = d
            moved.row.row -= 1
            return (key - 1, moved)
        })
    }
}

/// A set to write as one Registro row (column D kind, E load, F reps).
struct PlannedSet: Equatable {
    var kind: String
    var load: Double
    var reps: Int
}

/// Parts of a drop or rest-pause set typed in the same editor and written with it in one save.
enum ChainParts {
    /// Pause between parts when the exercise has none recorded: 10 s after a drop, 15 s in a rest-pause.
    static func defaultPause(_ kind: String) -> Int { SetKind.chainRest(kind) ?? 15 }

    /// Rows that get the pause when a set at `row` is saved with `parts` parts right after it:
    /// the set and every part but the last, whose rest the clock measures.
    static func pauseRows(after row: Int, parts: Int) -> [Int] {
        parts > 0 ? Array(row..<(row + parts)) : []
    }

    /// The rows written after the set for its parts. Every part but the last keeps the set's kind (Drop or
    /// Rest-pause) so the chain continues (3.1, 3.2…); the last is normal so the next set starts a new series.
    static func parts(_ minis: [(load: Double, reps: Int)], kind: String) -> [PlannedSet] {
        minis.enumerated().map { i, m in
            PlannedSet(kind: i == minis.count - 1 ? SetKind.normal : kind, load: m.load, reps: m.reps)
        }
    }

    /// Suggested reps for the first rest-pause part: about a third of the main set, at least 1.
    static func suggestedReps(after reps: Int) -> Int { max(1, Int((Double(reps) / 3).rounded())) }

    /// A drop's load: about 20 % less than the one before, rounded down to the unit's step.
    static func dropLoad(after load: Double, unit: WeightUnit) -> Double {
        let target = load * 0.8
        let step = unit.defaultStep(for: target)
        return max(0, (target / step).rounded(.down) * step)
    }

    /// "3" for the set itself, "3.1" for its first part (`part` counts from 0).
    static func label(serie: String, part: Int?) -> String {
        let base = serie.isEmpty ? "•" : serie
        return part.map { "\(base).\($0 + 1)" } ?? base
    }

    /// "47,5×8" as typed, with a dash for what is still empty.
    static func summary(load: String, reps: String) -> String {
        let l = load.trimmingCharacters(in: .whitespaces), r = reps.trimmingCharacters(in: .whitespaces)
        return "\(l.isEmpty ? "—" : l)×\(r.isEmpty ? "—" : r)"
    }

    /// Reps chips under the steppers: rest-pause parts are short, so they get low counts.
    static func repsChips(kind: String, editingPart: Bool) -> [Int] {
        editingPart && kind == SetKind.restPause ? [2, 3, 4, 5, 6] : [6, 8, 10, 12, 15]
    }

    /// What a new part starts with. Rest-pause: the same load, a third of the reps for the first part.
    /// Drop: about 20 % off the load, the same reps.
    static func nextPart(kind: String, load: Double?, reps: Int, first: Bool, unit: WeightUnit) -> (load: Double?, reps: Int) {
        if kind == SetKind.drop {
            return (load.map { dropLoad(after: $0, unit: unit) }, max(1, reps))
        }
        return (load, first ? suggestedReps(after: reps) : max(1, reps))
    }
}
