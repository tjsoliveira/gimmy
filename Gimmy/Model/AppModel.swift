import Foundation
import Observation
import UIKit

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

struct RestState: Codable, Equatable {
    var row: Int
    var exercise: String
    var day: String
    var start: Date
    var target: Int
    var alerted: Bool
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case needsConfig, signedOut, loading, ready, failed(String) }
    enum Tab: Hashable { case workout, history, setup }

    var phase: Phase = .loading
    var ledger = Ledger()
    var day = DayKey.from(Date())
    var routine: String?
    var busy: String?
    var banner: Banner?
    var signInError: String?
    var tab: Tab = .workout
    var workoutPath: [String] = []
    var historyPath: [String] = []
    var setupPath: [PlanRoute] = []
    /// The set open in the editor sheet.
    var entry: SetDraft?
    var entryError: String?
    /// Editor contents closed without saving, per set.
    var drafts = DraftStore()
    /// Any row of the exercise shown open on the workout screen.
    var focusedRow: Int?
    var addingExercise = false
    var finishing = false
    var rest: RestState?
    var highlightedRow: Int?

    let config: AppConfig
    private let auth: GoogleAuth
    /// Internal (not private) for the routine setup in AppModel+Plan.swift.
    let sheets: SheetsClient
    let defaults = UserDefaults.standard
    @ObservationIgnored var tabIDs: [String: Int] = [:]

    init() {
        let config = AppConfig.load()
        let auth = GoogleAuth(config: config)
        self.config = config
        self.auth = auth
        self.sheets = SheetsClient(spreadsheetID: config.spreadsheetID, auth: auth)
    }

    // MARK: - Derived state

    var currentRows: [SetRow] {
        guard let routine else { return [] }
        return ledger.sessionRows(day: day, routine: routine)
    }

    var currentSession: Session? {
        guard let routine else { return nil }
        return ledger.sessions().first { $0.day == day && $0.routine == routine }
    }

    /// Routines that already have sets on the selected day.
    var routinesOnDay: Set<String> {
        Set(ledger.rows.filter { $0.day == day && $0.reps != nil }.map(\.routine))
    }

    /// What the routine picker offers on the selected day: the routines in force, plus any already logged that day.
    var availableRoutines: [String] {
        let valid = ledger.routines(on: day)
        var seen = Set(valid)
        let logged = ledger.rows.filter { $0.day == day && $0.reps != nil && !$0.routine.isEmpty }.map(\.routine)
        return valid + logged.filter { seen.insert($0).inserted }
    }

    // MARK: - Lifecycle

    func start() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") { loadDemo(); return }
        #endif
        guard config.isComplete else { phase = .needsConfig; return }
        guard auth.hasSession else { phase = .signedOut; return }
        await initialLoad()
    }

    func signIn() async {
        signInError = nil
        do {
            try await auth.signIn()
            await initialLoad()
        } catch AuthError.cancelled {
            return
        } catch {
            signInError = error.localizedDescription
        }
    }

    func signOut() {
        auth.signOut()
        dismissRest()
        entry = nil
        focusedRow = nil
        ledger = Ledger()
        workoutPath = []
        historyPath = []
        setupPath = []
        phase = .signedOut
    }

    func initialLoad() async {
        phase = .loading
        do {
            try await loadAll()
            pickRoutine()
            phase = .ready
            restoreRest()
            ensureSelection()
        } catch {
            if isAuthError(error) {
                signInError = error.localizedDescription
                phase = .signedOut
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    #if DEBUG
    /// Sample data for the README screenshots: no Google account, nothing is written.
    private func loadDemo() {
        let tabs = DemoData.make()
        var next = Ledger()
        next.parsePlan(tabs.plan)
        next.parseExercises(tabs.exercises)
        next.parseRegistro(tabs.registro)
        ledger = next
        day = DayKey.from(Date())
        routine = "Costas"
        phase = .ready
        if let row = tabs.restRow, let x = ledger.row(row) {
            rest = RestState(row: x.row, exercise: x.exercise, day: x.day ?? day, start: Date().addingTimeInterval(-47),
                             target: ledger.restTarget(exercise: x.exercise, routine: x.routine, day: day), alerted: false)
        }
        setSessionStart(Date().addingTimeInterval(-38 * 60), day: day, routine: "Costas")
    }
    #endif

    func reload() async {
        if let message = await perform("Recarregando…", write: false, {
            try await self.loadAll()
            self.pickRoutine()
            self.ensureSelection()
        }) {
            show(message, error: true)
        }
    }

    private func loadAll() async throws {
        let plan = try await sheets.values("Rotinas!A1:L")
        async let exercises = sheets.values("'Exercícios'!A1:D")
        async let registro = sheets.values("Registro!A1:Q")
        let (e, r) = try await (exercises, registro)
        var next = Ledger()
        next.parsePlan(plan)
        next.parseExercises(e)
        next.parseRegistro(r)
        ledger = next
    }

    private func loadRegistro() async throws {
        ledger.parseRegistro(try await sheets.values("Registro!A1:Q"))
    }

    func loadPlan() async throws {
        ledger.parsePlan(try await sheets.values("Rotinas!A1:L"))
    }

    // MARK: - Selection

    func selectRoutine(_ value: String) {
        routine = value
        defaults.set(value, forKey: "treino")
        entry = nil
        focusedRow = nil
        ensureSelection()
    }

    func selectDay(_ value: String) {
        day = value
        if phase == .ready { pickRoutine() }
        entry = nil
        focusedRow = nil
        ensureSelection()
    }

    /// The routine logged on the day, else the current choice if still offered, else the last used, else the first.
    func pickRoutine() {
        if let today = ledger.rows.first(where: { $0.day == day && $0.reps != nil && !$0.routine.isEmpty }) {
            routine = today.routine
            return
        }
        let available = availableRoutines
        if let routine, available.contains(routine) { return }
        let saved = defaults.string(forKey: "treino")
        routine = saved.flatMap { available.contains($0) ? $0 : nil } ?? available.first
    }

    func openForEditing(_ session: Session) {
        day = session.day
        routine = session.routine
        workoutPath = []
        tab = .workout
        entry = nil
        focusedRow = nil
        ensureSelection()
    }

    // MARK: - Focus & quick entry

    /// The exercise shown open: the one holding `focusedRow`, else the first with sets left, else the last.
    var focusedGroup: ExerciseGroup? {
        let groups = ledger.groups(currentRows)
        if let focusedRow, let g = groups.first(where: { $0.rows.contains { $0.row == focusedRow } }) { return g }
        return groups.first(where: { $0.rows.contains { !$0.isDone } }) ?? groups.last
    }

    func focus(_ group: ExerciseGroup) {
        guard busy == nil else { return }
        focusedRow = group.rows.first?.row
    }

    /// Keeps the open exercise and the edited set valid after data changes.
    func ensureSelection() {
        let rows = currentRows
        guard !rows.isEmpty else { entry = nil; focusedRow = nil; return }
        if let e = entry, !rows.contains(where: { $0.row == e.row.row && $0.exercise == e.row.exercise }) { entry = nil }
        if let f = focusedRow, !rows.contains(where: { $0.row == f }) { focusedRow = nil }
    }

    /// Once an exercise has no sets left to log, opens the next one that has.
    private func advanceFocus(after row: Int) {
        let rows = currentRows
        let groups = ledger.groups(rows)
        guard let group = groups.first(where: { $0.rows.contains { $0.row == row } }),
              !group.rows.contains(where: { !$0.isDone }) else { return }
        let next = rows.first(where: { $0.row > row && !$0.isDone }) ?? rows.first(where: { !$0.isDone })
        if let next { focusedRow = next.row }
    }

    // MARK: - Workout

    func startSession() async {
        guard let routine else { return }
        var alreadyThere = false
        let error = await perform("Montando o treino…", write: true) {
            try await self.loadRegistro()
            if !self.currentRows.isEmpty { alreadyThere = true; return }
            let t = self.ledger.template(routine: routine, day: self.day)
            guard !t.rows.isEmpty else { return }
            let start = self.ledger.registroRowCount + 1
            var values: [[OutCell]] = []
            for (i, x) in t.rows.enumerated() {
                let firstOfExercise = i == 0 || t.rows[i - 1].exercise != x.exercise
                values.append([
                    i == 0 ? .number(Double(DayKey.serial(self.day))) : .blank,
                    i == 0 ? .text(routine) : .blank,
                    firstOfExercise ? .text(x.exercise) : .blank,
                    .text(x.kind),
                    .blank,
                    .number(Double(x.reps)),
                ])
            }
            try await self.sheets.update("Registro!A\(start):F\(start + values.count - 1)", values)
            try await self.loadRegistro()
            self.defaults.set(routine, forKey: "treino")
            self.setSessionStart(Date(), day: self.day, routine: routine)
        }
        if let error { show(error, error: true); return }
        ensureSelection()
        show(alreadyThere ? "Esse treino já estava na planilha." : "Treino montado. Registre a primeira série.")
    }

    func select(_ x: SetRow) {
        guard busy == nil else { return }
        setEntry(x)
    }

    private func setEntry(_ x: SetRow) {
        if var kept = drafts.draft(for: x) {
            kept.row = x
            kept.last = ledger.lastSet(for: x)
            entry = kept
        } else {
            entry = draft(for: x)
        }
        entryError = nil
        focusedRow = x.row
    }

    /// The user closed the editor without saving: keep what they filled in for next time.
    func dismissEditor() {
        if let e = entry {
            if e.differs(from: draft(for: e.row)) { drafts.stash(e) } else { drafts.remove(e.row.row) }
        }
        entry = nil
        entryError = nil
    }

    /// A draft kept for this set, if any (shown as "pré-definida" in the list).
    func preset(for x: SetRow) -> SetDraft? {
        guard !x.isDone, let d = drafts.draft(for: x), d.differs(from: draft(for: x)) else { return nil }
        return d
    }

    func draft(for x: SetRow) -> SetDraft {
        let last = ledger.lastSet(for: x)
        let load = x.load ?? last?.load
        let unit = ledger.unit(of: x.exercise)
        let rest = (x.rest ?? x.pendingRest).map { Fmt.duration(Double($0)) } ?? ""
        return SetDraft(
            row: x,
            last: last,
            load: Fmt.loadInput(load),
            reps: String(x.reps ?? last?.reps ?? 10),
            kind: x.kind,
            unit: unit,
            step: unit.defaultStep(for: load),
            rest: rest
        )
    }

    /// Returns an error to show next to the set, or nil once saved.
    func save(_ d: SetDraft, clear: Bool) async -> String? {
        let x = d.row
        let load = Parse.number(d.load)
        let reps = Int(d.reps.trimmingCharacters(in: .whitespaces)) ?? 0
        if !clear {
            guard let load, load >= 0 else { return "Informe a carga em \(d.unit.rawValue) (use 0 para peso do corpo)." }
            guard reps > 0 else { return "Informe quantas reps você fez." }
        }
        var restProvided = false
        var newRest: Int?
        if !clear && x.isDone {
            switch RestInput.parse(d.rest) {
            case .invalid:
                return "Descanso: use minutos e segundos, por exemplo 1:30."
            case .empty:
                restProvided = true
            case .seconds(let s):
                if s > 3600 { return "Descanso: use minutos e segundos, por exemplo 1:30." }
                restProvided = true
                newRest = s
            }
        }
        // Rest-pause parts typed in the same editor become new rows right after this set.
        var parts: [PlannedSet] = []
        if !clear && d.kind == SetKind.restPause && !d.minis.isEmpty && !ledger.hasContinuation(x) {
            var minis: [(load: Double, reps: Int)] = []
            for m in d.minis {
                guard let l = Parse.number(m.load), l >= 0, let r = Int(m.reps.trimmingCharacters(in: .whitespaces)), r > 0 else {
                    return "Confira carga e reps das mini-séries do rest-pause."
                }
                minis.append((l, r))
            }
            parts = RestPause.parts(minis)
        }
        RestAlerts.requestPermission()

        var conflict = false
        var message = ""
        var restAnchor = x.row
        let error = await perform(clear ? "Limpando…" : "Salvando…", write: true) {
            guard try await self.verify(x) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            let kindChanged = d.kind != x.kind
            let wasDone = x.isDone
            let loadCell: OutCell = clear ? .blank : .number(load ?? 0)
            let repsCell: OutCell = clear ? (x.reps.map { OutCell.number(Double($0)) } ?? .blank) : .number(Double(reps))
            try await self.sheets.update("Registro!D\(x.row):F\(x.row)", [[.text(d.kind), loadCell, repsCell]])
            self.mutate(x.row) { y in
                y.kind = d.kind
                if clear { y.load = nil } else { y.load = load; y.reps = reps }
            }
            self.drafts.remove(x.row)

            let restChanged = restProvided && newRest != x.rest
            if restChanged {
                let cell = newRest.map { OutCell.number(Double($0) / 86400) } ?? .blank
                try await self.sheets.update("Registro!P\(x.row)", [[cell]])
                self.mutate(x.row) { y in y.rest = newRest; y.pendingRest = nil }
            }

            let unitChanged = !clear && d.unit != self.ledger.unit(of: x.exercise)
            if unitChanged { try await self.setUnit(x.exercise, d.unit) }

            if !parts.isEmpty {
                try await self.sheets.insertRows(sheetID: AppConfig.registroSheetID, after: x.row, count: parts.count)
                self.shiftRest(after: x.row, by: parts.count)
                self.drafts.shift(after: x.row, by: parts.count)
                let values: [[OutCell]] = parts.map { [.blank, .blank, .blank, .text($0.kind), .number($0.load), .number(Double($0.reps))] }
                try await self.sheets.update("Registro!A\(x.row + 1):F\(x.row + parts.count)", values)
                try await self.loadRegistro()
                restAnchor = x.row + parts.count
            }

            if kindChanged { self.ledger.renumber() }
            if self.entry?.row.row == x.row { self.entry = nil }

            guard let saved = self.ledger.row(x.row) else { return }
            if clear {
                message = "Série limpa."
            } else {
                var pieces = [self.ledgerPartsLabel(parts.count)]
                if let delta = self.ledger.delta(saved, self.ledger.lastSet(for: saved)) {
                    pieces.append(delta.isUp ? "+\(Fmt.n1(delta.value)) no 1RM" : delta.isDown ? "−\(Fmt.n1(-delta.value)) no 1RM" : "igual à última")
                }
                if restChanged { pieces.append(newRest.map { "descanso \(Fmt.duration(Double($0)))" } ?? "descanso apagado") }
                if unitChanged { pieces.append("\(x.exercise) agora em \(d.unit.rawValue)") }
                message = pieces.joined(separator: " · ") + "."
            }

            if !clear && (!wasDone || !parts.isEmpty) {
                self.startRest(after: self.ledger.row(restAnchor) ?? saved)
                let day = saved.day ?? self.day
                if self.sessionStart(day: day, routine: saved.routine) == nil {
                    self.setSessionStart(Date().addingTimeInterval(-60), day: day, routine: saved.routine)
                }
            }
            if clear && self.rest?.row == x.row { self.dismissRest() }
        }
        if conflict {
            entry = nil
            ensureSelection()
            show("A planilha mudou desde que você abriu o app. Confira a série e salve de novo.", error: true)
            return nil
        }
        if let error { return error }
        if !clear { advanceFocus(after: restAnchor) }
        show(message)
        return nil
    }

    private func ledgerPartsLabel(_ count: Int) -> String {
        count == 0 ? "Série salva" : "Rest-pause salvo com \(count) \(count == 1 ? "mini-série" : "mini-séries")"
    }

    func addSet(to group: ExerciseGroup) async {
        guard let last = group.rows.last else { return }
        var conflict = false
        let error = await perform("Adicionando série…", write: true) {
            guard try await self.verify(last) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            try await self.sheets.insertRows(sheetID: AppConfig.registroSheetID, after: last.row, count: 1)
            self.shiftRest(after: last.row, by: 1)
            self.drafts.shift(after: last.row, by: 1)
            try await self.sheets.update("Registro!A\(last.row + 1):F\(last.row + 1)", [[.blank, .blank, .blank, .blank, .blank, .number(Double(last.reps ?? 10))]])
            try await self.loadRegistro()
        }
        if conflict { show("A planilha mudou. Confira e toque em Adicionar série de novo.", error: true); return }
        if let error { show(error, error: true); return }
        if let next = ledger.row(last.row + 1) { select(next) }
    }

    /// Returns an error to show in the sheet, or nil once it can close.
    func addExercise(name raw: String, sets: Int, reps: Int, unit: WeightUnit) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Escolha ou escreva o exercício." }
        guard (1...12).contains(sets) else { return "Use de 1 a 12 séries." }
        guard reps > 0 else { return "Informe as reps." }
        guard let last = currentRows.last else { return nil }
        var conflict = false
        let error = await perform("Adicionando…", write: true) {
            guard try await self.verify(last) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            try await self.sheets.insertRows(sheetID: AppConfig.registroSheetID, after: last.row, count: sets)
            self.shiftRest(after: last.row, by: sets)
            self.drafts.shift(after: last.row, by: sets)
            let values: [[OutCell]] = (0..<sets).map { i in
                [.blank, .blank, i == 0 ? .text(name) : .blank, .blank, .blank, .number(Double(reps))]
            }
            try await self.sheets.update("Registro!A\(last.row + 1):F\(last.row + sets)", values)
            if !self.ledger.exercises.contains(name) || unit != self.ledger.unit(of: name) {
                try await self.setUnit(name, unit)
            }
            try await self.loadRegistro()
        }
        if conflict {
            addingExercise = false
            show("A planilha mudou. Confira e tente de novo.", error: true)
            return nil
        }
        if let error { return error }
        addingExercise = false
        if let first = ledger.row(last.row + 1) { focusedRow = first.row }
        show("\(name) adicionado com \(sets) \(sets == 1 ? "série" : "séries").")
        return nil
    }

    /// Deletes the set's row. Date, routine, exercise name and duration live on the first row,
    /// so they move to the next row first. Returns an error to show in the editor, or nil once it can close.
    func remove(_ d: SetDraft) async -> String? {
        let x = d.row
        var conflict = false
        var endsChain = false
        let error = await perform("Removendo…", write: true) {
            guard try await self.verify(x) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            let start = max(2, x.row - 1)
            let offset = x.row - start
            let raw = try await self.sheets.values("Registro!A\(start):Q\(x.row + 1)")
            func line(_ i: Int) -> [Cell] { i < raw.count ? raw[i] : [] }
            func filled(_ c: Cell) -> Bool { c != .empty }
            let previous: [Cell]? = offset > 0 ? line(0) : nil
            let current = line(offset)
            let next = line(offset + 1)

            let sameSession = filled(next.at(5)) && Parse.day(next.at(12)) == x.day && Parse.text(next.at(13)) == x.routine
            let sameExercise = sameSession && Parse.text(next.at(14)) == x.exercise
            // Removing the last set of a drop or rest-pause chain would make the next set continue it;
            // the set before goes back to normal.
            if let previous {
                endsChain = SetKind.chains(Parse.text(previous.at(3)))
                    && Parse.day(previous.at(12)) == x.day
                    && Parse.text(previous.at(14)) == x.exercise
                    && !SetKind.chains(x.kind)
            }

            if sameSession {
                let head: [OutCell] = [
                    filled(current.at(0)) && !filled(next.at(0)) ? .number(Double(DayKey.serial(x.day ?? self.day))) : .skip,
                    filled(current.at(1)) && !filled(next.at(1)) ? .text(Parse.text(current.at(1))) : .skip,
                    sameExercise && filled(current.at(2)) && !filled(next.at(2)) ? .text(Parse.text(current.at(2))) : .skip,
                ]
                if head.contains(where: { if case .skip = $0 { return false } else { return true } }) {
                    try await self.sheets.update("Registro!A\(x.row + 1):C\(x.row + 1)", [head])
                }
                if let minutes = Parse.minutes(current.at(16)), !filled(next.at(16)) {
                    try await self.sheets.update("Registro!Q\(x.row + 1)", [[.number(Double(minutes) / 1440)]])
                }
            }
            if endsChain {
                try await self.sheets.update("Registro!D\(x.row - 1)", [[.blank]])
            }
            try await self.sheets.deleteRow(sheetID: AppConfig.registroSheetID, row: x.row)
            self.drafts.removeAndShift(x.row)
            if let rest = self.rest {
                if rest.row == x.row {
                    self.dismissRest()
                } else if rest.row > x.row {
                    self.rest?.row -= 1
                    self.saveRest()
                }
            }
            if self.entry?.row.row == x.row { self.entry = nil }
            try await self.loadRegistro()
            self.ensureSelection()
        }
        if conflict {
            entry = nil
            ensureSelection()
            show("A planilha mudou desde que você abriu o app. Confira e tente de novo.", error: true)
            return nil
        }
        if let error { return error }
        show(endsChain ? "Série removida. A série anterior voltou a ser normal." : "Série removida.")
        return nil
    }

    func setUnit(_ exercise: String, _ unit: WeightUnit) async throws {
        if let row = ledger.exerciseSheetRow[exercise] {
            try await sheets.update("'Exercícios'!D\(row)", [[.text(unit.rawValue)]])
        } else {
            let row = ledger.exerciseRowCount + 1
            try await sheets.update("'Exercícios'!A\(row):D\(row)", [[.text(exercise), .blank, .blank, .text(unit.rawValue)]])
            ledger.exercises.append(exercise)
            ledger.exerciseSheetRow[exercise] = row
            ledger.exerciseRowCount = row
        }
        ledger.units[exercise] = unit
    }

    // MARK: - Finish

    func suggestedDuration() -> Int? {
        guard let z = currentSession else { return nil }
        if let d = ledger.stats(z).duration { return d }
        guard let started = sessionStart(day: z.day, routine: z.routine) else { return nil }
        let minutes = Int((Date().timeIntervalSince(started) / 60).rounded())
        return minutes > 0 && minutes < 300 ? minutes : nil
    }

    // MARK: - Session clock

    /// Bumped whenever a start time changes, so views reading it refresh.
    private var clockVersion = 0

    func sessionStart(day: String, routine: String) -> Date? {
        _ = clockVersion
        let t = defaults.double(forKey: startKey(day, routine))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private func setSessionStart(_ date: Date?, day: String, routine: String) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: startKey(day, routine))
        } else {
            defaults.removeObject(forKey: startKey(day, routine))
        }
        clockVersion += 1
    }

    /// Total-time clock for the workout on screen.
    var sessionClock: SessionClock.State {
        guard let routine else { return .hidden }
        let rows = currentRows
        return SessionClock.state(
            start: sessionStart(day: day, routine: routine),
            hasSession: !rows.isEmpty,
            finished: rows.first?.duration != nil,
            isToday: day == DayKey.from(Date()),
            now: Date()
        )
    }

    /// Starts the clock now, for a workout whose start time is unknown.
    func startClock() {
        guard let routine else { return }
        setSessionStart(Date(), day: day, routine: routine)
    }

    func finish(minutes raw: String) async -> String? {
        guard let z = currentSession, let first = z.rows.first else { return nil }
        guard let minutes = Int(raw.trimmingCharacters(in: .whitespaces)), minutes > 0, minutes < 600 else {
            return "Informe a duração do treino em minutos."
        }
        var conflict = false
        let error = await perform("Finalizando…", write: true) {
            guard try await self.verify(first) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            try await self.sheets.update("Registro!Q\(first.row)", [[.number(Double(minutes) / 1440)]])
            self.mutate(first.row) { $0.duration = minutes }
        }
        if conflict {
            finishing = false
            show("A planilha mudou. Confira e tente de novo.", error: true)
            return nil
        }
        if let error { return error }
        finishing = false
        dismissRest()
        setSessionStart(nil, day: z.day, routine: z.routine)
        tab = .history
        historyPath = [z.key]
        show("Treino finalizado · \(Fmt.minutes(minutes)).")
        Task { await resync() }
        return nil
    }

    // MARK: - Rest timer

    private func startRest(after x: SetRow) {
        let target = SetKind.chainRest(x.kind) ?? ledger.restTarget(exercise: x.exercise, routine: x.routine, day: x.day ?? day)
        let state = RestState(row: x.row, exercise: x.exercise, day: x.day ?? day, start: Date(), target: target, alerted: false)
        rest = state
        saveRest()
        RestAlerts.schedule(after: target, exercise: x.exercise)
        watch(state)
    }

    private func watch(_ state: RestState) {
        let remaining = Double(state.target) - Date().timeIntervalSince(state.start)
        guard remaining > 0, !state.alerted else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard let self, var current = self.rest, current.start == state.start, !current.alerted else { return }
            current.alerted = true
            self.rest = current
            self.saveRest()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Rows inserted above the set being rested move it down; keep the timer pointing at the same set.
    private func shiftRest(after row: Int, by count: Int) {
        guard let rest, rest.row > row else { return }
        self.rest?.row += count
        saveRest()
    }

    func dismissRest() {
        rest = nil
        defaults.removeObject(forKey: "rest")
        RestAlerts.cancel()
    }

    func recordRest() async {
        guard let state = rest, busy == nil else { return }
        let seconds = Int(Date().timeIntervalSince(state.start).rounded())
        dismissRest()
        guard let x = ledger.rows.first(where: { $0.row == state.row && $0.exercise == state.exercise && $0.day == state.day }) else {
            show("Não achei a série desse descanso (\(Fmt.duration(Double(seconds)))). Preencha no campo de descanso da série.", error: true)
            return
        }
        var ok = false
        var conflict = false
        _ = await perform("Registrando descanso…", write: true) {
            guard try await self.verify(x) else {
                try await self.loadRegistro()
                conflict = true
                return
            }
            try await self.sheets.update("Registro!P\(x.row)", [[.number(Double(seconds) / 86400)]])
            self.mutate(x.row) { $0.rest = seconds }
            ok = true
        }
        if ok {
            show("Descanso de \(Fmt.duration(Double(seconds))) registrado.")
            highlightNext(after: x)
            return
        }
        if conflict {
            show("A planilha mudou e o descanso não foi registrado.", error: true)
            return
        }
        // Keep the measured time on the set so it can be saved from the set's editor.
        if let i = ledger.rows.firstIndex(where: { $0.row == state.row && $0.exercise == state.exercise && $0.day == state.day }) {
            ledger.rows[i].pendingRest = seconds
            show("O descanso de \(Fmt.duration(Double(seconds))) não foi gravado. Toque na série para salvar de novo.", error: true)
        }
    }

    private func highlightNext(after x: SetRow) {
        let rows = currentRows
        guard let i = rows.firstIndex(where: { $0.row == x.row }) else { return }
        guard let next = rows[(i + 1)...].first(where: { !$0.isDone }) ?? rows.first(where: { !$0.isDone }) else { return }
        highlightedRow = next.row
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.highlightedRow == next.row { self?.highlightedRow = nil }
        }
    }

    private func saveRest() {
        guard let rest, let data = try? JSONEncoder().encode(rest) else { return }
        defaults.set(data, forKey: "rest")
    }

    private func restoreRest() {
        guard let data = defaults.data(forKey: "rest"),
              let state = try? JSONDecoder().decode(RestState.self, from: data),
              Date().timeIntervalSince(state.start) < 30 * 60,
              let x = ledger.rows.first(where: { $0.row == state.row && $0.exercise == state.exercise && $0.day == state.day }),
              x.isDone, x.rest == nil
        else {
            defaults.removeObject(forKey: "rest")
            return
        }
        rest = state
        watch(state)
    }

    // MARK: - Plumbing

    func show(_ text: String, error: Bool = false) {
        let banner = Banner(text: text, isError: error)
        self.banner = banner
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 6 : 3.2))
            if self?.banner == banner { self?.banner = nil }
        }
    }

    private func startKey(_ day: String, _ routine: String) -> String { "start:\(day)|\(routine)" }

    private func mutate(_ row: Int, _ change: (inout SetRow) -> Void) {
        if let i = ledger.rows.firstIndex(where: { $0.row == row }) { change(&ledger.rows[i]) }
    }

    /// Confirms the row still holds what we think it holds before writing to it.
    private func verify(_ x: SetRow) async throws -> Bool {
        let v = try await sheets.values("Registro!D\(x.row):O\(x.row)").first ?? []
        return Parse.text(v.at(0)) == x.kind
            && Parse.number(v.at(1)) == x.load
            && Parse.number(v.at(2)).map({ Int($0.rounded()) }) == x.reps
            && Parse.day(v.at(9)) == x.day
            && Parse.text(v.at(10)) == x.routine
            && Parse.text(v.at(11)) == x.exercise
    }

    /// Runs one sheet operation at a time. Returns a message on failure.
    func perform(_ label: String, write: Bool, _ operation: () async throws -> Void) async -> String? {
        guard busy == nil else { return "Espere a operação em andamento terminar." }
        busy = label
        defer { busy = nil }
        do {
            try await operation()
            return nil
        } catch {
            if write, let e = error as? SheetsError, e.isUncertain {
                // The write may have reached the sheet: re-read it so the list shows what was saved.
                Task { await self.resync() }
            }
            return describe(error, write: write)
        }
    }

    /// Re-reads the Registro tab in the background, keeping the screen as is if it fails.
    private func resync() async {
        guard phase == .ready, let values = try? await sheets.values("Registro!A1:Q") else { return }
        ledger.parseRegistro(values)
        ensureSelection()
    }

    private func describe(_ error: Error, write: Bool) -> String {
        if isAuthError(error) {
            entry = nil
            addingExercise = false
            finishing = false
            signInError = "O acesso ao Google expirou. Entre de novo."
            phase = .signedOut
            return signInError ?? ""
        }
        if write, let e = error as? SheetsError, e.isUncertain {
            return "A conexão caiu e não sei se gravou. Estou relendo a planilha: confira se a série aparece como concluída antes de salvar de novo."
        }
        return error.localizedDescription
    }

    private func isAuthError(_ error: Error) -> Bool {
        if let e = error as? SheetsError { return e.kind == .auth }
        if let e = error as? AuthError {
            switch e {
            case .notSignedIn, .expired, .invalidGrant: return true
            default: return false
            }
        }
        return false
    }
}
