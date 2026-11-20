import Foundation

/// Reordering the series of one exercise in a workout. A series is a set plus the drop or rest-pause
/// parts right after it (3, 3.1, 3.2), and it always moves as a whole, so a part never leaves its set.
/// The sheet rows stay where they are (the first ones hold the date, routine, exercise name and duration);
/// what moves between them is each set's content. The routine's configuration follows (see `planFollow`),
/// so the next workout copied from it keeps the new order.
enum SeriesOrder {
    /// Sets of one exercise, by type in order, split into series (indexes): a part (3.1) joins the series before it.
    static func blocks(kinds: [String]) -> [[Int]] {
        var out: [[Int]] = []
        for (i, label) in Series.labels(kinds).enumerated() {
            if label.contains("."), !out.isEmpty {
                out[out.count - 1].append(i)
            } else {
                out.append([i])
            }
        }
        return out
    }

    /// The exercise's rows (in sheet order) split into series, as indexes into `rows`.
    static func blocks(_ rows: [SetRow]) -> [[Int]] { blocks(kinds: rows.map(\.kind)) }

    /// What a dragged series carries: its first row.
    static func dragPayload(row: Int) -> String { "gimmy-series:\(row)" }

    static func row(fromPayload payload: String) -> Int? {
        let prefix = "gimmy-series:"
        return payload.hasPrefix(prefix) ? Int(payload.dropFirst(prefix.count)) : nil
    }

    /// Which series (index into `blocks`) holds the row numbered `row`.
    static func block(of row: Int, in rows: [SetRow]) -> Int? {
        guard let i = rows.firstIndex(where: { $0.row == row }) else { return nil }
        return blocks(rows).firstIndex { $0.contains(i) }
    }

    /// The new order after moving series `from` to position `to`: for each row position, the index in `rows`
    /// whose content goes there. The other series keep their order. Nil when nothing moves, or when a series
    /// ending in Drop or Rest-pause with no part after it would stop being the last one: the next set would
    /// then read as its continuation.
    static func move(_ rows: [SetRow], series from: Int, to: Int) -> [Int]? {
        move(kinds: rows.map(\.kind), series: from, to: to)
    }

    static func move(kinds: [String], series from: Int, to: Int) -> [Int]? {
        var list = blocks(kinds: kinds)
        guard from != to, list.indices.contains(from), list.indices.contains(to) else { return nil }
        let moved = list.remove(at: from)
        list.insert(moved, at: to)
        for block in list.dropLast() {
            if let last = block.last, SetKind.chains(kinds[last]) { return nil }
        }
        return list.flatMap { $0 }
    }

    /// What the routine's configuration does when a series moves in the workout.
    enum PlanFollow: Equatable {
        /// The exercise isn't in the routine: the new order is only for this workout.
        case notInRoutine
        /// Its sets aren't configured: the next workout copies this one, so the order carries over by itself.
        case followsLastWorkout
        /// Configured with a different number of series than this workout: the configuration is left as it is.
        case differs
        /// The configured sets, reordered the same way, to write in the routine.
        case reorder([PlanSet])
    }

    /// `plan` is the exercise's planned sets in the routine (nil when it isn't there); `workoutSeries` how many
    /// series it has in this workout. The workout was copied from the plan, so series N here is series N there.
    static func planFollow(plan: (sets: [PlanSet], source: Ledger.PlanSource)?, workoutSeries: Int, from: Int, to: Int) -> PlanFollow {
        guard let plan else { return .notInRoutine }
        guard plan.source == .configured else { return .followsLastWorkout }
        let kinds = plan.sets.map(\.kind)
        guard blocks(kinds: kinds).count == workoutSeries, let order = move(kinds: kinds, series: from, to: to) else {
            return .differs
        }
        return .reorder(order.map { plan.sets[$0] })
    }
}

/// One Registro row as read from columns D to P, checked and copied by the app.
enum RegistroRow {
    /// Whether the cells (D…O, or D…P) still hold what the app shows for this set.
    static func matches(_ cells: [Cell], _ x: SetRow) -> Bool {
        Parse.text(cells.at(0)) == x.kind
            && Parse.number(cells.at(1)) == x.load
            && Parse.number(cells.at(2)).map({ Int($0.rounded()) }) == x.reps
            && Parse.day(cells.at(9)) == x.day
            && Parse.text(cells.at(10)) == x.routine
            && Parse.text(cells.at(11)) == x.exercise
    }

    /// A set's own content from a D…P read, ready to write on another row:
    /// type, load, reps and notes (D…G), and the rest after it (P).
    static func content(_ cells: [Cell]) -> (dToG: [OutCell], rest: OutCell) {
        ([copy(cells.at(0)), copy(cells.at(1)), copy(cells.at(2)), copy(cells.at(3), literal: true)], copy(cells.at(12)))
    }

    private static func copy(_ cell: Cell, literal: Bool = false) -> OutCell {
        switch cell {
        case .number(let v): return .number(v)
        case .text(let s): return literal ? .literal(s) : .text(s)
        case .bool(let b): return .text(b ? "TRUE" : "FALSE")
        case .empty: return .blank
        }
    }
}
