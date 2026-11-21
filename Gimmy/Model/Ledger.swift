import Foundation

/// How an exercise's load is measured, from the Unidade column of the Exercícios tab ("kg", "lb" or "placas").
/// Placas counts the plates of a machine's stack: it has no weight in kg.
enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg, lb
    case plates = "placas"

    static let poundInKg = 0.45359237

    /// Reads the Unidade column; anything unknown is kg.
    static func parse(_ raw: String) -> WeightUnit {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "lb", "lbs": return .lb
        case "placa", "placas": return .plates
        default: return .kg
        }
    }

    /// Short label for the unit toggle.
    var toggleTitle: String {
        switch self {
        case .kg: return "KG"
        case .lb: return "LBS"
        case .plates: return "PLACAS"
        }
    }

    /// Kilograms per unit of load. Plates have no weight in kg, so they stay out of the volume.
    var kgFactor: Double {
        switch self {
        case .kg: return 1
        case .lb: return Self.poundInKg
        case .plates: return 0
        }
    }

    /// Quick-add chips under the load in the entry card: each tap adds its value.
    var cardAdds: [Double] {
        switch self {
        case .kg: return [1, 2.5, 5, 10, 20]
        case .lb: return [2.5, 5, 10, 20, 45]
        case .plates: return [1, 2, 3, 4, 5]
        }
    }

    func defaultStep(for load: Double?) -> Double {
        switch self {
        case .lb: return (load.map { $0 < 25 } ?? false) ? 2.5 : 5
        case .kg: return (load.map { $0 < 12 } ?? false) ? 1 : 2.5
        case .plates: return 1
        }
    }
}

enum SetKind {
    static let normal = ""
    static let drop = "Drop"
    static let restPause = "Rest-pause"
    static let failure = "Falha"
    static let warmup = "Aquecimento"

    /// Drop and Rest-pause chain the next set into the same series.
    static func chains(_ kind: String) -> Bool { kind == drop || kind == restPause }

    /// Inside a chain the pause is short: 10 s to strip the plates after a drop,
    /// 15 s of breathing after a rest-pause.
    static func chainRest(_ kind: String) -> Int? {
        switch kind {
        case drop: return 10
        case restPause: return 15
        default: return nil
        }
    }
}

/// One line of the "Registro" tab.
struct SetRow: Identifiable, Hashable {
    var row: Int            // 1-based sheet row
    var kind: String        // D: "", Drop, Rest-pause, Falha, Aquecimento
    var load: Double?       // E
    var reps: Int?          // F
    var serie = ""          // H, recomputed locally
    var day: String?        // M (auto)
    var routine: String     // N (auto)
    var exercise: String    // O (auto)
    var rest: Int?          // P, seconds
    var duration: Int?      // Q, minutes (first row of a session)
    var pendingRest: Int?   // measured but not saved

    var id: Int { row }
    var isDone: Bool { load != nil && reps != nil }
    var isWarmup: Bool { kind == SetKind.warmup }
}

/// One line of the "Rotinas" tab: an exercise of a routine version.
/// A line with the routine name but no exercise keeps a routine that has no exercises yet.
struct PlanItem: Hashable {
    var row: Int            // 1-based sheet row
    var routine: String     // A
    var order: Double?      // B
    var exercise: String    // C
    var sets: Double?       // F, number of series
    var reps: String        // G, "15-12-10-6"
    var notes: String       // H
    var rest: Double?       // I, seconds
    var kinds: String = ""  // J, set types aligned with G; empty on lines the app never configured
    var start: String?      // K, first day the routine is valid
    var end: String?        // L, last day; empty while it is the current one
}

struct ExerciseGroup: Identifiable, Hashable {
    var exercise: String
    var rows: [SetRow]
    var id: Int { rows.first?.row ?? 0 }
}

struct Session: Identifiable, Hashable {
    var key: String
    var day: String
    var routine: String
    var rows: [SetRow]
    var id: String { key }
}

struct ExerciseStatus {
    enum Kind { case first, up, down, flat }
    var kind: Kind
    var value: Double

    var text: String {
        switch kind {
        case .first: return "1ª vez"
        case .up: return "Subiu +" + Fmt.n1(value)
        case .down: return "Caiu −" + Fmt.n1(-value)
        case .flat: return "Manteve"
        }
    }
}

/// Change in estimated 1RM against the same set last time.
struct SetDelta {
    var value: Double
    var isUp: Bool { value > 0 }
    var isDown: Bool { value < 0 }
}

struct ExerciseSummary: Identifiable {
    var group: ExerciseGroup
    var status: ExerciseStatus?
    var record: Bool
    var id: Int { group.id }
}

struct SessionStats {
    var volume: Double
    var previousVolume: Double?
    var previousDay: String?
    var totalSeries: Int
    var doneSeries: Int
    var pending: Int
    var averageRest: Double?
    var duration: Int?
    var exercises: [ExerciseSummary]

    var volumeChange: Double? {
        guard let previousVolume, previousVolume > 0 else { return nil }
        return volume / previousVolume - 1
    }
    var records: Int { exercises.filter(\.record).count }
    var upCount: Int { exercises.filter { $0.status?.kind == .up }.count }
    var downCount: Int { exercises.filter { $0.status?.kind == .down }.count }
}

struct TemplateRow: Equatable {
    var exercise: String
    var kind: String
    var reps: Int
}

struct Template {
    var rows: [TemplateRow]
}

struct PlannedExercise: Identifiable {
    var id: Int
    var exercise: String
    var sets: Int
}

enum OneRM {
    /// Brzycki up to 10 reps, Epley above.
    static func estimate(_ load: Double?, _ reps: Int?) -> Double? {
        guard let c = load, let r = reps, r > 0, r < 37 else { return nil }
        let r1 = Double(r)
        let v = r <= 10 ? c * 36 / (37 - r1) : c * (1 + r1 / 30)
        return (v * 10).rounded() / 10
    }
}

/// Everything read from the spreadsheet, plus the rules the old page applied to it.
struct Ledger {
    var plan: [PlanItem] = []
    var versions: [RoutineVersion] = []
    var planRowCount = 1
    var exercises: [String] = []
    var exerciseSheetRow: [String: Int] = [:]
    var units: [String: WeightUnit] = [:]
    var exerciseRowCount = 1
    var rows: [SetRow] = []
    var registroRowCount = 1

    // MARK: Parsing

    mutating func parsePlan(_ values: [[Cell]]) {
        planRowCount = max(1, values.count)
        plan = values.dropFirst().enumerated().map { i, r in
            PlanItem(
                row: i + 2,
                routine: Parse.text(r.at(0)),
                order: Parse.number(r.at(1)),
                exercise: Parse.text(r.at(2)),
                sets: Parse.number(r.at(5)),
                reps: Parse.text(r.at(6)),
                notes: Parse.text(r.at(7)),
                rest: Parse.number(r.at(8)),
                kinds: Parse.text(r.at(9)),
                start: Parse.day(r.at(10)),
                end: Parse.day(r.at(11))
            )
        }.filter { !$0.routine.isEmpty }
        versions = RoutineVersion.group(plan)
    }

    mutating func parseExercises(_ values: [[Cell]]) {
        exerciseRowCount = max(1, values.count)
        exercises = []
        units = [:]
        exerciseSheetRow = [:]
        for (i, r) in values.dropFirst().enumerated() {
            let name = Parse.text(r.at(0))
            if name.isEmpty { continue }
            exercises.append(name)
            exerciseSheetRow[name] = i + 2
            units[name] = WeightUnit.parse(Parse.text(r.at(3)))
        }
    }

    mutating func parseRegistro(_ values: [[Cell]]) {
        registroRowCount = max(1, values.count)
        var out: [SetRow] = []
        for (i, r) in values.dropFirst().enumerated() {
            out.append(SetRow(
                row: i + 2,
                kind: Parse.text(r.at(3)),
                load: Parse.number(r.at(4)),
                reps: Parse.number(r.at(5)).map { Int($0.rounded()) },
                day: Parse.day(r.at(12)),
                routine: Parse.text(r.at(13)),
                exercise: Parse.text(r.at(14)),
                rest: Parse.seconds(r.at(15)),
                duration: Parse.minutes(r.at(16))
            ))
        }
        rows = out
        renumber()
    }

    /// Same rule as the sheet's Série column: every set advances the number,
    /// except a set that follows one marked Drop or Rest-pause, which continues it as X.1, X.2.
    mutating func renumber() {
        var lists: [String: [Int]] = [:]
        for (i, x) in rows.enumerated() {
            guard let day = x.day, !x.exercise.isEmpty else { continue }
            lists["\(day)|\(x.exercise)", default: []].append(i)
        }
        for indices in lists.values {
            let labels = Series.labels(indices.map { rows[$0].kind })
            for (j, i) in indices.enumerated() { rows[i].serie = labels[j] }
        }
    }

    // MARK: Lookups

    func unit(of exercise: String) -> WeightUnit { units[exercise] ?? .kg }
    func kgFactor(_ exercise: String) -> Double { unit(of: exercise).kgFactor }
    func row(_ number: Int) -> SetRow? { rows.first { $0.row == number } }

    /// Planned rest for an exercise: from the routine version in force on `day` when given, else any line of it.
    func restTarget(exercise: String, routine: String?, day: String? = nil) -> Int {
        let current = routine.flatMap { name in day.flatMap { version(named: name, on: $0) } }
        let item = current.flatMap { v in plan.first { v.rows.contains($0.row) && $0.exercise == exercise } }
            ?? plan.first { $0.routine == routine && $0.exercise == exercise }
            ?? plan.first { $0.exercise == exercise }
        if let rest = item?.rest, rest > 0 { return Int(rest) }
        return 90
    }

    func sessionRows(day: String, routine: String) -> [SetRow] {
        rows.filter { $0.day == day && $0.routine == routine && $0.reps != nil }
    }

    func groups(_ list: [SetRow]) -> [ExerciseGroup] {
        var out: [ExerciseGroup] = []
        for x in list {
            if var last = out.last, last.exercise == x.exercise, last.rows.last?.row == x.row - 1 {
                last.rows.append(x)
                out[out.count - 1] = last
            } else {
                out.append(ExerciseGroup(exercise: x.exercise, rows: [x]))
            }
        }
        return out
    }

    func latestDay(before day: String, where match: (SetRow) -> Bool) -> String? {
        var best: String?
        for x in rows where x.isDone && match(x) {
            if let d = x.day, d < day, best.map({ d > $0 }) ?? true { best = d }
        }
        return best
    }

    func previousDay(exercise: String, before day: String) -> String? {
        latestDay(before: day) { $0.exercise == exercise }
    }

    func previousSessionDay(routine: String, before day: String) -> String? {
        latestDay(before: day) { $0.routine == routine }
    }

    func sets(exercise: String, day: String) -> [SetRow] {
        rows.filter { $0.exercise == exercise && $0.day == day && $0.isDone }
    }

    /// Whether the row right after `x` continues its series (X.1, X.2…).
    func hasContinuation(_ x: SetRow) -> Bool {
        guard let next = row(x.row + 1) else { return false }
        return next.exercise == x.exercise && next.day == x.day && next.serie.contains(".")
    }

    /// The pause between the parts of a drop or rest-pause (`kind`) the last time this exercise had one recorded,
    /// before `day`. Only rows followed by another part count: the last part's rest is the rest after the whole set.
    func lastChainPause(kind: String, exercise: String, before day: String) -> Int? {
        let pauses = rows.filter { x in
            x.exercise == exercise && x.kind == kind && x.rest != nil
                && (x.day.map { $0 < day } ?? false) && hasContinuation(x)
        }
        let latest = pauses.max { ($0.day ?? "", $0.row) < ($1.day ?? "", $1.row) }
        return latest?.rest
    }

    func lastSet(for x: SetRow) -> SetRow? {
        guard let day = x.day, let p = previousDay(exercise: x.exercise, before: day) else { return nil }
        return rows.first { $0.exercise == x.exercise && $0.day == p && $0.serie == x.serie && $0.isDone }
    }

    // MARK: Progress

    func best(_ list: [SetRow]) -> Double? {
        var best: Double?
        for y in list where !y.isWarmup && y.isDone {
            if let v = OneRM.estimate(y.load, y.reps), best.map({ v > $0 }) ?? true { best = v }
        }
        return best
    }

    func delta(_ a: SetRow?, _ b: SetRow?) -> SetDelta? {
        guard let a, let b, let x = OneRM.estimate(a.load, a.reps), let y = OneRM.estimate(b.load, b.reps) else { return nil }
        return SetDelta(value: ((x - y) * 10).rounded() / 10)
    }

    func status(_ g: ExerciseGroup, day: String) -> ExerciseStatus? {
        let done = g.rows.filter(\.isDone)
        if done.isEmpty { return nil }
        if previousDay(exercise: g.exercise, before: day) == nil { return ExerciseStatus(kind: .first, value: 0) }
        var sum = 0.0, n = 0
        for x in done {
            if let d = delta(x, lastSet(for: x)) { sum += d.value; n += 1 }
        }
        if n == 0 { return nil }
        sum = (sum * 10).rounded() / 10
        return ExerciseStatus(kind: sum > 0 ? .up : sum < 0 ? .down : .flat, value: sum)
    }

    /// A record only counts when the exercise also went up (sum of set variations > 0).
    func isRecord(_ g: ExerciseGroup, day: String) -> Bool {
        guard status(g, day: day)?.kind == .up, let today = best(g.rows) else { return false }
        let earlier = rows.filter { x in x.exercise == g.exercise && (x.day.map { $0 < day } ?? false) }
        guard let before = best(earlier) else { return false }
        return today > before
    }

    func volume(_ list: [SetRow]) -> Double {
        list.filter { $0.isDone && !$0.isWarmup }
            .reduce(0) { $0 + ($1.load ?? 0) * Double($1.reps ?? 0) * kgFactor($1.exercise) }
    }

    func volume(routine: String, day: String) -> Double {
        volume(rows.filter { $0.routine == routine && $0.day == day })
    }

    // MARK: Sessions

    /// Exercises and set counts shown before a workout starts; drop and rest-pause sets don't count as new sets.
    func plannedExercises(_ t: Template) -> [PlannedExercise] {
        var out: [PlannedExercise] = []
        var previousKind = ""
        for x in t.rows {
            if var last = out.last, last.exercise == x.exercise {
                if !SetKind.chains(previousKind) { last.sets += 1 }
                out[out.count - 1] = last
            } else {
                out.append(PlannedExercise(id: out.count, exercise: x.exercise, sets: 1))
            }
            previousKind = x.kind
        }
        return out
    }

    func sessions() -> [Session] {
        var map: [String: Session] = [:]
        for x in rows {
            guard let day = x.day, !x.routine.isEmpty, x.reps != nil else { continue }
            let key = "\(day)|\(x.routine)"
            map[key, default: Session(key: key, day: day, routine: x.routine, rows: [])].rows.append(x)
        }
        return map.values
            .filter { $0.rows.contains(where: \.isDone) }
            .sorted { ($0.day + $0.routine) > ($1.day + $1.routine) }
    }

    func session(_ key: String) -> Session? { sessions().first { $0.key == key } }

    /// Today's workout before Finalizar: its volume is still partial, so it isn't compared with the last one yet.
    /// Older sessions without a duration (never finalized) keep their comparison.
    func isInProgress(_ z: Session, today: String) -> Bool {
        z.day == today && !z.rows.contains { $0.duration != nil }
    }

    func stats(_ z: Session) -> SessionStats {
        let done = z.rows.filter(\.isDone)
        let series = z.rows.filter { !$0.serie.contains(".") }
        let rests = done.compactMap(\.rest)
        let p = previousSessionDay(routine: z.routine, before: z.day)
        return SessionStats(
            volume: volume(z.rows),
            previousVolume: p.map { volume(routine: z.routine, day: $0) },
            previousDay: p,
            totalSeries: series.count,
            doneSeries: series.filter(\.isDone).count,
            pending: z.rows.filter { !$0.isDone }.count,
            averageRest: rests.isEmpty ? nil : Double(rests.reduce(0, +)) / Double(rests.count),
            duration: z.rows.compactMap(\.duration).first,
            exercises: groups(z.rows).map { g in
                ExerciseSummary(group: g, status: status(g, day: z.day), record: isRecord(g, day: z.day))
            }
        )
    }
}
