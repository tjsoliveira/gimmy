import Foundation

/// One value per session day, for the evolution charts.
struct EvolutionPoint: Identifiable, Equatable {
    let day: String
    let date: Date
    let value: Double
    var id: String { day }
}

enum EvolutionPeriod: String, CaseIterable, Identifiable {
    case threeMonths = "3 meses"
    case sixMonths = "6 meses"
    case year = "1 ano"
    case all = "Tudo"

    var id: String { rawValue }

    /// First day included, or nil for everything.
    func since(_ today: Date = Date()) -> String? {
        let months: Int
        switch self {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .year: months = 12
        case .all: return nil
        }
        guard let start = Calendar.current.date(byAdding: .month, value: -months, to: today) else { return nil }
        return DayKey.from(start)
    }
}

enum RoutineMetric: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case duration = "Duração"
    case series = "Séries"

    var id: String { rawValue }
    /// Whether a rise is progress (colors the change green/red). Duration is neutral.
    var higherIsBetter: Bool { self != .duration }
}

enum ExerciseMetric: String, CaseIterable, Identifiable {
    case oneRM = "1RM est."
    case topLoad = "Carga máx."
    case volume = "Volume"

    var id: String { rawValue }
}

extension Ledger {
    private func inPeriod(_ day: String, since: String?) -> Bool {
        since.map { day >= $0 } ?? true
    }

    /// Routine metric per session, oldest first.
    func routineSeries(_ routine: String, metric: RoutineMetric, since: String?) -> [EvolutionPoint] {
        sessions()
            .filter { $0.routine == routine && inPeriod($0.day, since: since) }
            .sorted { $0.day < $1.day }
            .compactMap { z in
                guard let date = DayKey.date(z.day) else { return nil }
                let value: Double?
                switch metric {
                case .volume:
                    value = volume(z.rows)
                case .duration:
                    value = z.rows.compactMap(\.duration).first.map(Double.init)
                case .series:
                    value = Double(z.rows.filter { $0.isDone && !$0.serie.contains(".") }.count)
                }
                return value.map { EvolutionPoint(day: z.day, date: date, value: $0) }
            }
    }

    /// Exercise metric per day it was trained, oldest first. Warm-up sets don't count.
    func exerciseSeries(_ exercise: String, metric: ExerciseMetric, since: String?) -> [EvolutionPoint] {
        let days = Set(rows.compactMap { x in x.exercise == exercise && x.isDone ? x.day : nil })
        return days
            .filter { inPeriod($0, since: since) }
            .sorted()
            .compactMap { day in
                guard let date = DayKey.date(day) else { return nil }
                let work = sets(exercise: exercise, day: day).filter { !$0.isWarmup }
                guard !work.isEmpty else { return nil }
                let value: Double?
                switch metric {
                case .oneRM: value = best(work)
                case .topLoad: value = work.compactMap(\.load).max()
                case .volume: value = volume(work)
                }
                return value.map { EvolutionPoint(day: day, date: date, value: $0) }
            }
    }

    /// Exercises of a routine: the planned order first, then any others logged in it.
    func exercises(inRoutine routine: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let planned = plan.enumerated()
            .filter { $0.element.routine == routine }
            .sorted { ($0.element.order ?? 99, $0.offset) < ($1.element.order ?? 99, $1.offset) }
            .map(\.element.exercise)
        for name in planned + rows.filter({ $0.routine == routine && $0.isDone }).map(\.exercise) where !name.isEmpty {
            if seen.insert(name).inserted { out.append(name) }
        }
        return out
    }

    /// Every exercise with at least one logged set, alphabetically.
    func loggedExercises() -> [String] {
        Set(rows.filter(\.isDone).map(\.exercise))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
