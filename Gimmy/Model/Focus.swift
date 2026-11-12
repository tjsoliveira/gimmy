import Foundation

/// Which exercise the workout screen shows open. The others show as compact cards,
/// with a check once all their sets are logged.
enum Focus {
    /// The exercise holding `focusedRow` (the one the user opened), else the first with sets left.
    /// Nil once every set is logged, so every exercise closes with its check.
    static func group(_ groups: [ExerciseGroup], focusedRow: Int?) -> ExerciseGroup? {
        if let focusedRow, let g = groups.first(where: { $0.rows.contains { $0.row == focusedRow } }) { return g }
        return groups.first(where: { $0.rows.contains { !$0.isDone } })
    }

    /// The row to focus after `row` is saved: unchanged while its exercise has sets left,
    /// then the next set to log, or nil when nothing is left.
    static func after(_ row: Int, rows: [SetRow], groups: [ExerciseGroup], current: Int?) -> Int? {
        guard let group = groups.first(where: { $0.rows.contains { $0.row == row } }),
              !group.rows.contains(where: { !$0.isDone }) else { return current }
        return (rows.first(where: { $0.row > row && !$0.isDone }) ?? rows.first(where: { !$0.isDone }))?.row
    }
}
