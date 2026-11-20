import Foundation

/// A routine built from a workout that was changed along the way (a set's type, sets or exercises added,
/// removed or moved). Offered when the workout is finished; it becomes a new version of the routine.
enum NewRoutine {
    /// One exercise of the routine being built.
    struct Item: Equatable {
        var exercise: String
        var sets: [PlanSet]
        var notes: String
        var rest: Double?
    }

    /// What the current routine has for an exercise: its sets (with the target reps), notes and planned rest.
    struct Planned {
        var sets: [PlanSet]
        var notes: String
        var rest: Double?
    }

    /// Whether the workout's structure (exercises in order, each set's type) differs from what Começar treino
    /// copies: the routine in force, or the last workout for exercises without configured sets.
    /// Loads and the reps done don't count: they change every time.
    static func changed(session rows: [SetRow], template: Template) -> Bool {
        let done = rows.filter { !$0.exercise.isEmpty }.map { "\($0.exercise)|\($0.kind)" }
        let planned = template.rows.map { "\($0.exercise)|\($0.kind)" }
        return done != planned
    }

    /// The routine's exercises from the workout, in the order they were done, with every set (done or not).
    /// A set in the same place as one in the current routine (same series and part: 3, 3.1) keeps that target;
    /// a new one takes the reps from the workout. Notes and planned rest come from the current routine.
    static func items(session rows: [SetRow], plan: [String: Planned]) -> [Item] {
        var order: [String] = []
        var byExercise: [String: [SetRow]] = [:]
        for x in rows where !x.exercise.isEmpty {
            if byExercise[x.exercise] == nil { order.append(x.exercise) }
            byExercise[x.exercise, default: []].append(x)
        }
        return order.map { name in
            let sets = byExercise[name] ?? []
            let planned = plan[name]
            var targets: [String: Int] = [:]
            if let planned {
                for (label, set) in zip(Series.labels(planned.sets.map(\.kind)), planned.sets) { targets[label] = set.reps }
            }
            let labels = Series.labels(sets.map(\.kind))
            return Item(
                exercise: name,
                sets: zip(labels, sets).map { label, x in PlanSet(kind: x.kind, reps: targets[label] ?? x.reps ?? 10) },
                notes: planned?.notes ?? "",
                rest: planned?.rest
            )
        }
    }
}
