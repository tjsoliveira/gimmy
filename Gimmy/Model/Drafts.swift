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
    /// Rest-pause parts after this set; written as new rows on save.
    var minis: [MiniSet] = []
    /// Pause between the rest-pause parts ("0:10"), written on the set and every part but the last.
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

enum RestPause {
    /// Pause between parts when the exercise has none recorded yet.
    static let defaultPause = SetKind.chainRest(SetKind.restPause) ?? 15

    /// Rows that get the pause when a set at `row` is saved with `parts` parts right after it:
    /// the set and every part but the last, whose rest the clock measures.
    static func pauseRows(after row: Int, parts: Int) -> [Int] {
        parts > 0 ? Array(row..<(row + parts)) : []
    }

    /// The rows written after a rest-pause set for its parts. Every part but the last stays
    /// Rest-pause so the chain continues (3.1, 3.2…); the last is normal so the next set starts a new series.
    static func parts(_ minis: [(load: Double, reps: Int)]) -> [PlannedSet] {
        minis.enumerated().map { i, m in
            PlannedSet(kind: i == minis.count - 1 ? SetKind.normal : SetKind.restPause, load: m.load, reps: m.reps)
        }
    }

    /// Suggested reps for a new part: about a third of the main set, at least 1.
    static func suggestedReps(after reps: Int) -> Int { max(1, Int((Double(reps) / 3).rounded())) }
}
