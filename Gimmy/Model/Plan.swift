import Foundation

/// Series numbers as the sheet's Série column computes them: every set advances the number,
/// except a set right after a Drop or Rest-pause, which continues it as X.1, X.2.
enum Series {
    static func labels(_ kinds: [String]) -> [String] {
        var n = 0, k = 0
        return kinds.indices.map { j in
            if j > 0 && SetKind.chains(kinds[j - 1]) {
                k += 1
                return "\(n).\(k)"
            }
            n += 1
            k = 0
            return "\(n)"
        }
    }

    /// How many series a list of sets makes (chain parts don't count).
    static func count(_ kinds: [String]) -> Int { labels(kinds).filter { !$0.contains(".") }.count }
}

/// One planned set of an exercise in a routine: its type and target reps.
struct PlanSet: Identifiable, Equatable {
    let id = UUID()
    var kind: String
    var reps: Int

    static func == (a: PlanSet, b: PlanSet) -> Bool { a.kind == b.kind && a.reps == b.reps }
}

/// Reading and writing the planned sets of a Rotinas line: G holds the reps ("15-12-10-6"),
/// J the types in the same order ("Aquecimento, Normal, Normal, Drop").
enum PlanSets {
    static let maxSets = 20

    static func name(of kind: String) -> String { kind.isEmpty ? "Normal" : kind }

    static func kind(named raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let known = [SetKind.warmup, SetKind.drop, SetKind.restPause, SetKind.failure]
        return known.first { $0.caseInsensitiveCompare(s) == .orderedSame } ?? SetKind.normal
    }

    static func reps(_ text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
    }

    /// The sets saved by the app (J filled), or nil for a line it never configured.
    static func configured(kinds: String, reps text: String) -> [PlanSet]? {
        guard !kinds.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let names = kinds.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let counts = Self.reps(text)
        let n = min(maxSets, max(names.count, counts.count))
        return (0..<n).map { i in
            PlanSet(kind: i < names.count ? Self.kind(named: names[i]) : SetKind.normal,
                    reps: i < counts.count ? counts[i] : (counts.last ?? 10))
        }
    }

    /// A line typed by hand: F series of normal sets, reps from G.
    static func fromSheet(sets: Double?, reps text: String) -> [PlanSet] {
        let counts = Self.reps(text)
        let planned = sets.map { $0.isFinite ? Int(min(max($0, 0), Double(maxSets))) : 0 } ?? 0
        let n = planned > 0 ? planned : (counts.isEmpty ? 3 : min(counts.count, maxSets))
        return (0..<n).map { PlanSet(kind: SetKind.normal, reps: $0 < counts.count ? counts[$0] : (counts.last ?? 10)) }
    }

    /// Columns F (series), G (reps) and J (types) for a set list.
    static func columns(_ sets: [PlanSet]) -> (series: Int, reps: String, kinds: String) {
        (Series.count(sets.map(\.kind)),
         sets.map { String($0.reps) }.joined(separator: "-"),
         sets.map { name(of: $0.kind) }.joined(separator: ", "))
    }
}

/// A routine with its dates. The same name can come back with new dates (a new version of the plan);
/// the Registro tab only stores the name, so a day's version is the one whose dates hold that day.
struct RoutineVersion: Identifiable, Hashable {
    enum Status { case current, upcoming, ended }

    var name: String
    var start: String?
    var end: String?
    /// Its lines in the Rotinas tab, including an empty placeholder line.
    var rows: [Int]

    var id: String { Self.id(name, start) }
    static func id(_ name: String, _ start: String?) -> String { "\(name)|\(start ?? "")" }

    func isValid(on day: String) -> Bool {
        (start.map { $0 <= day } ?? true) && (end.map { day <= $0 } ?? true)
    }

    func status(today: String) -> Status {
        if let end, end < today { return .ended }
        if let start, start > today { return .upcoming }
        return .current
    }

    func overlaps(start otherStart: String?, end otherEnd: String?) -> Bool {
        let open = "9999-12-31"
        return (start ?? "") <= (otherEnd ?? open) && (otherStart ?? "") <= (end ?? open)
    }

    /// Lines with the same name and start date form one version. If its lines disagree on the end, the earliest wins.
    static func group(_ plan: [PlanItem]) -> [RoutineVersion] {
        var out: [RoutineVersion] = []
        for item in plan {
            let id = Self.id(item.routine, item.start)
            if let i = out.firstIndex(where: { $0.id == id }) {
                out[i].rows.append(item.row)
                if let end = item.end, out[i].end.map({ end < $0 }) ?? true { out[i].end = end }
            } else {
                out.append(RoutineVersion(name: item.routine, start: item.start, end: item.end, rows: [item.row]))
            }
        }
        return out
    }
}

enum RoutineRules {
    /// An error to show, or nil when a routine can be saved with this name and dates.
    static func validate(name raw: String, start: String?, end: String?, others: [RoutineVersion]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Dê um nome ao treino." }
        if let start, let end, end < start { return "A data de fim vem antes da de início." }
        if let clash = others.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.overlaps(start: start, end: end)
        }) {
            return "As datas se sobrepõem às do outro \(clash.name) (\(Fmt.validity(clash.start, clash.end).lowercased())). Ajuste a vigência de um dos dois."
        }
        return nil
    }
}

extension Ledger {
    /// Where an exercise's planned sets come from.
    enum PlanSource: Equatable {
        /// Saved in the Configurar tab.
        case configured
        /// Not configured yet: copied from the last time it was done in this routine.
        case lastSession(String)
        /// Not configured yet and never done: from the Séries and Reps columns.
        case sheet
    }

    /// Routines in force on `day`, in sheet order.
    func routines(on day: String) -> [String] {
        var seen = Set<String>()
        return versions.filter { $0.isValid(on: day) }.map(\.name).filter { seen.insert($0).inserted }
    }

    /// The version of `name` in force on `day`; if two overlap, the one that started last.
    func version(named name: String, on day: String) -> RoutineVersion? {
        versions.filter { $0.name == name && $0.isValid(on: day) }.max { ($0.start ?? "") < ($1.start ?? "") }
    }

    func version(id: String) -> RoutineVersion? { versions.first { $0.id == id } }

    /// The exercises of a version in their order (Ordem, then sheet order).
    func items(of v: RoutineVersion) -> [PlanItem] {
        plan.filter { v.rows.contains($0.row) && !$0.exercise.isEmpty }
            .sorted { ($0.order ?? 999, $0.row) < ($1.order ?? 999, $1.row) }
    }

    func planItem(exercise: String, routine: String, day: String) -> PlanItem? {
        guard let v = version(named: routine, on: day) else { return nil }
        return items(of: v).first { $0.exercise == exercise }
    }

    /// Days with logged sets under this version's name and dates.
    func sessionDays(of v: RoutineVersion) -> [String] {
        Set(rows.filter { $0.routine == v.name && $0.isDone }.compactMap(\.day).filter { v.isValid(on: $0) }).sorted()
    }

    /// The sets a workout gets for this exercise.
    func plannedSets(_ item: PlanItem, before day: String) -> (sets: [PlanSet], source: PlanSource) {
        if let sets = PlanSets.configured(kinds: item.kinds, reps: item.reps) { return (sets, .configured) }
        let match: (SetRow) -> Bool = { $0.routine == item.routine && $0.exercise == item.exercise }
        if let p = latestDay(before: day, where: match) {
            let done = rows.filter { match($0) && $0.day == p && $0.isDone }
            return (done.map { PlanSet(kind: $0.kind, reps: $0.reps ?? 10) }, .lastSession(p))
        }
        return (PlanSets.fromSheet(sets: item.sets, reps: item.reps), .sheet)
    }

    /// A copy of the routine in force on `day`: its exercises, set types and reps, loads left empty.
    func template(routine: String, day: String) -> Template {
        guard let v = version(named: routine, on: day) else { return Template(rows: []) }
        var out: [TemplateRow] = []
        for item in items(of: v) {
            for s in plannedSets(item, before: day).sets {
                out.append(TemplateRow(exercise: item.exercise, kind: s.kind, reps: s.reps))
            }
        }
        return Template(rows: out)
    }
}
