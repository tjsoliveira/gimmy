#if DEBUG
import Foundation

/// A sample spreadsheet for the README screenshots (launch argument `-demo`).
/// Debug builds only: with it the app signs in to nothing and writes nothing.
enum DemoData {
    struct Tabs {
        var plan: [[Cell]]
        var exercises: [[Cell]]
        var registro: [[Cell]]
        /// The logged set whose rest clock is running.
        var restRow: Int?
    }

    private struct Exercise {
        let name: String
        let group: String
        let equipment: String
        let base: Double
        let kinds: [String]
        let reps: [Int]
        let rest: Int
        var notes = ""
    }

    private struct Routine {
        let name: String
        let start: Int
        let end: Int?
        let exercises: [Exercise]
    }

    private static let N = SetKind.normal, W = SetKind.warmup, D = SetKind.drop, R = SetKind.restPause, F = SetKind.failure

    private static let costas = Routine(name: "Costas", start: -35, end: nil, exercises: [
        Exercise(name: "Seated Row (Cable)", group: "Costas", equipment: "Cabo", base: 40,
                 kinds: [W, N, N, N], reps: [15, 12, 10, 8], rest: 120, notes: "1ª de aquecimento"),
        Exercise(name: "Lat Pulldown (Machine)", group: "Costas", equipment: "Máquina", base: 50,
                 kinds: [N, N, N, D, N], reps: [12, 10, 8, 8, 10], rest: 90, notes: "4ª com drop até a falha"),
        Exercise(name: "Lat Pulldown (Single Arm)", group: "Costas", equipment: "Cabo", base: 25,
                 kinds: [N, N, F], reps: [12, 10, 10], rest: 60),
        Exercise(name: "Straight-Arm Pulldown (Cable)", group: "Costas", equipment: "Cabo", base: 15,
                 kinds: [N, N, R, R, N], reps: [12, 12, 10, 4, 3], rest: 60, notes: "3ª em rest-pause: 15 s de pausa, repete 2x"),
    ])

    private static let peito = Routine(name: "Peito", start: -35, end: nil, exercises: [
        Exercise(name: "Incline Bench Press (Dumbbell)", group: "Peito", equipment: "Halteres", base: 22,
                 kinds: [W, N, N, N], reps: [15, 12, 10, 8], rest: 120, notes: "1ª de aquecimento"),
        Exercise(name: "Chest Fly (Machine)", group: "Peito", equipment: "Máquina", base: 45,
                 kinds: [N, N, N, D, N], reps: [12, 10, 8, 8, 10], rest: 90, notes: "4ª com drop até a falha"),
        Exercise(name: "Cable Crossover", group: "Peito", equipment: "Cabo", base: 10,
                 kinds: [N, N, N], reps: [15, 12, 10], rest: 60),
    ])

    private static let pernas = Routine(name: "Pernas", start: -35, end: nil, exercises: [
        Exercise(name: "Squat (Smith Machine)", group: "Pernas", equipment: "Smith", base: 40,
                 kinds: [W, N, N, N], reps: [12, 10, 8, 8], rest: 120, notes: "1ª de aquecimento"),
        Exercise(name: "Leg Press", group: "Pernas", equipment: "Máquina", base: 160,
                 kinds: [N, N, N, N], reps: [12, 10, 10, 8], rest: 120),
        Exercise(name: "Leg Extension (Machine)", group: "Pernas", equipment: "Máquina", base: 50,
                 kinds: [N, N, D, N], reps: [12, 10, 8, 10], rest: 90, notes: "3ª com drop até a falha"),
        Exercise(name: "Seated Leg Curl (Machine)", group: "Pernas", equipment: "Máquina", base: 45,
                 kinds: [N, N, N], reps: [12, 10, 10], rest: 90),
    ])

    private static let ombroAntigo = Routine(name: "Ombro", start: -120, end: -36, exercises: [
        Exercise(name: "Shoulder Press (Machine)", group: "Ombro", equipment: "Máquina", base: 35,
                 kinds: [N, N, N], reps: [12, 10, 8], rest: 90),
        Exercise(name: "Lateral Raise (Dumbbell)", group: "Ombro", equipment: "Halteres", base: 8,
                 kinds: [N, N, N], reps: [12, 12, 10], rest: 60),
    ])

    private static let ombro = Routine(name: "Ombro", start: -35, end: nil, exercises: [
        Exercise(name: "Shoulder Press (Machine)", group: "Ombro", equipment: "Máquina", base: 40,
                 kinds: [W, N, N, D, N], reps: [12, 10, 8, 6, 8], rest: 120, notes: "1ª de aquecimento; 4ª com drop até a falha"),
        Exercise(name: "Lateral Raise (Dumbbell)", group: "Ombro", equipment: "Halteres", base: 10,
                 kinds: [N, N, R, R, N], reps: [12, 10, 8, 4, 3], rest: 60, notes: "3ª em rest-pause"),
        Exercise(name: "Reverse Fly (Cable)", group: "Ombro", equipment: "Cabo", base: 5,
                 kinds: [N, N, N], reps: [12, 10, 10], rest: 60),
    ])

    private static let bracos = Routine(name: "Braços", start: 5, end: nil, exercises: [
        Exercise(name: "Biceps Curl (Barbell)", group: "Braços", equipment: "Barra", base: 20,
                 kinds: [N, N, N], reps: [12, 10, 8], rest: 60),
        Exercise(name: "Triceps Pushdown (Rope)", group: "Braços", equipment: "Cabo", base: 15,
                 kinds: [N, N, N], reps: [12, 10, 8], rest: 60),
    ])

    private static let routines = [costas, peito, pernas, ombroAntigo, ombro, bracos]

    /// Past sessions, oldest first: day offset, routine, how many times it was done before, minutes.
    private static let sessions: [(day: Int, routine: Routine, level: Int, minutes: Int)] = [
        (-47, ombroAntigo, 0, 45), (-40, ombroAntigo, 1, 48),
        (-14, costas, 0, 54), (-13, peito, 0, 61), (-12, pernas, 0, 49), (-11, ombro, 0, 57),
        (-7, costas, 1, 52), (-6, peito, 1, 63), (-5, pernas, 1, 47), (-4, ombro, 1, 58),
    ]

    static func make(today: Date = Date()) -> Tabs {
        func day(_ offset: Int) -> String {
            DayKey.from(Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today)
        }

        var plan: [[Cell]] = [[]]
        for r in routines {
            for (i, x) in r.exercises.enumerated() {
                let cols = PlanSets.columns(zip(x.kinds, x.reps).map { PlanSet(kind: $0, reps: $1) })
                plan.append([
                    .text(r.name), .number(Double(i + 1)), .text(x.name), .empty, .empty,
                    .number(Double(cols.series)), .text(cols.reps), x.notes.isEmpty ? .empty : .text(x.notes),
                    .number(Double(x.rest)), .text(cols.kinds), .text(day(r.start)), r.end.map { Cell.text(day($0)) } ?? .empty,
                ])
            }
        }

        var exercises: [[Cell]] = [[]]
        var seen = Set<String>()
        for x in routines.flatMap(\.exercises) where seen.insert(x.name).inserted {
            exercises.append([.text(x.name), .text(x.group), .text(x.equipment), .text("kg")])
        }

        var registro: [[Cell]] = [[]]
        var restRow: Int?
        func add(_ r: Routine, day key: String, level: Int, minutes: Int?, isDone: (Int, Int) -> Bool) {
            var first = true
            let total = r.exercises.enumerated().reduce(0) { n, e in n + e.element.kinds.indices.filter { isDone(e.offset, $0) }.count }
            var logged = 0
            for (xi, x) in r.exercises.enumerated() {
                let setLoads = Self.loads(x, level: level)
                for (j, kind) in x.kinds.enumerated() {
                    let done = isDone(xi, j)
                    var row = [Cell](repeating: .empty, count: 17)
                    if first {
                        row[0] = .text(key)
                        row[1] = .text(r.name)
                    }
                    if j == 0 { row[2] = .text(x.name) }
                    row[3] = kind.isEmpty ? .empty : .text(kind)
                    row[4] = done ? .number(setLoads[j]) : .empty
                    row[5] = .number(Double(x.reps[j]))
                    row[12] = .text(key)
                    row[13] = .text(r.name)
                    row[14] = .text(x.name)
                    if done {
                        logged += 1
                        if logged < total {
                            let jitter = [4, -7, 11, -3, 6, 0, 9][(xi + j) % 7]
                            let seconds = SetKind.chainRest(kind).map { $0 + abs(jitter) % 4 } ?? x.rest + jitter
                            row[15] = .number(Double(seconds) / 86400)
                        } else if minutes == nil {
                            restRow = registro.count + 1
                        }
                    }
                    if first, let minutes { row[16] = .number(Double(minutes) / 1440) }
                    first = false
                    registro.append(row)
                }
            }
        }

        for s in sessions {
            add(s.routine, day: day(s.day), level: s.level, minutes: s.minutes) { _, _ in true }
        }
        // Today: the first exercise done, two sets of the second, the rest still open.
        add(costas, day: day(0), level: 2, minutes: nil) { xi, j in xi == 0 || (xi == 1 && j < 2) }

        return Tabs(plan: plan, exercises: exercises, registro: registro, restRow: restRow)
    }

    /// Loads for one session: warm-up at 60 %, work sets climbing, drops at 70 % of the set before,
    /// rest-pause parts at the same load. `level` adds one step per earlier session.
    private static func loads(_ x: Exercise, level: Int) -> [Double] {
        let step = x.base >= 20 ? 2.5 : 1
        func snap(_ v: Double) -> Double { max(step, (v / step).rounded() * step) }
        var out: [Double] = []
        var work = 0
        for (i, kind) in x.kinds.enumerated() {
            if kind == SetKind.warmup {
                out.append(snap(x.base * 0.6))
            } else if i > 0 && SetKind.chains(x.kinds[i - 1]) {
                out.append(x.kinds[i - 1] == SetKind.drop ? snap(out[i - 1] * 0.7) : out[i - 1])
            } else {
                out.append(snap(x.base + Double(work) * step * 2 + Double(level) * step))
                work += 1
            }
        }
        return out
    }
}
#endif
