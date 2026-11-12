import Foundation

enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg, lb

    static let poundInKg = 0.45359237

    var steps: [Double] { self == .lb ? [2.5, 5, 10] : [1, 2.5, 5] }

    func defaultStep(for load: Double?) -> Double {
        switch self {
        case .lb: return (load.map { $0 < 25 } ?? false) ? 2.5 : 5
        case .kg: return (load.map { $0 < 12 } ?? false) ? 1 : 2.5
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

/// One line of the "Rotinas" tab.
struct PlanItem {
    var routine: String
    var order: Double?
    var exercise: String
    var sets: Double?
    var reps: String
    var notes: String
    var rest: Double?
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

struct TemplateRow {
    var exercise: String
    var kind: String
    var reps: Int
}

struct Template {
    var previousDay: String?
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
    var routines: [String] = []
    var exercises: [String] = []
    var exerciseSheetRow: [String: Int] = [:]
    var units: [String: WeightUnit] = [:]
    var exerciseRowCount = 1
    var rows: [SetRow] = []
    var registroRowCount = 1

    // MARK: Parsing

    mutating func parsePlan(_ values: [[Cell]]) {
        plan = values.dropFirst().map { r in
            PlanItem(
                routine: Parse.text(r.at(0)),
                order: Parse.number(r.at(1)),
                exercise: Parse.text(r.at(2)),
                sets: Parse.number(r.at(5)),
                reps: Parse.text(r.at(6)),
                notes: Parse.text(r.at(7)),
                rest: Parse.number(r.at(8))
            )
        }.filter { !$0.routine.isEmpty && !$0.exercise.isEmpty }
        var seen = Set<String>()
        routines = plan.map(\.routine).filter { seen.insert($0).inserted }
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
            units[name] = Parse.text(r.at(3)).lowercased() == "lb" ? .lb : .kg
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
            var n = 0, k = 0
            for (j, i) in indices.enumerated() {
                if j > 0 && SetKind.chains(rows[indices[j - 1]].kind) {
                    k += 1
                    rows[i].serie = "\(n).\(k)"
                } else {
                    n += 1
                    k = 0
                    rows[i].serie = "\(n)"
                }
            }
        }
    }

    // MARK: Lookups

    func unit(of exercise: String) -> WeightUnit { units[exercise] ?? .kg }
    func kgFactor(_ exercise: String) -> Double { unit(of: exercise) == .lb ? WeightUnit.poundInKg : 1 }
    func row(_ number: Int) -> SetRow? { rows.first { $0.row == number } }

    func restTarget(exercise: String, routine: String?) -> Int {
        let item = plan.first { $0.routine == routine && $0.exercise == exercise } ?? plan.first { $0.exercise == exercise }
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

    private func latestDay(before day: String, where match: (SetRow) -> Bool) -> String? {
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

    func template(routine: String, day: String) -> Template {
        if let p = previousSessionDay(routine: routine, before: day) {
            let source = rows.filter { $0.routine == routine && $0.day == p && $0.isDone }
            return Template(previousDay: p, rows: source.map { TemplateRow(exercise: $0.exercise, kind: $0.kind, reps: $0.reps ?? 10) })
        }
        let items = plan.enumerated()
            .filter { $0.element.routine == routine }
            .sorted { a, b in
                let x = a.element.order ?? 99, y = b.element.order ?? 99
                return x == y ? a.offset < b.offset : x < y
            }
            .map(\.element)
        var out: [TemplateRow] = []
        for item in items {
            let reps = item.reps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
            let planned = Int(item.sets ?? 0)
            let n = planned > 0 ? planned : (reps.isEmpty ? 3 : reps.count)
            for i in 0..<n {
                out.append(TemplateRow(exercise: item.exercise, kind: SetKind.normal, reps: i < reps.count ? reps[i] : (reps.last ?? 10)))
            }
        }
        return Template(previousDay: nil, rows: out)
    }

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
