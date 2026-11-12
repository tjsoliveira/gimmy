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

/// What the set editor works on; saved only when the user taps Salvar.
struct SetDraft: Identifiable {
    let row: SetRow
    let last: SetRow?
    var load: String
    var reps: String
    var kind: String
    var unit: WeightUnit
    var step: Double
    var rest: String
    var id: Int { row.row }
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case needsConfig, signedOut, loading, ready, failed(String) }
    enum Tab: Hashable { case workout, history }

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
    var editing: SetDraft?
    var addingExercise = false
    var finishing = false
    var rest: RestState?
    var highlightedRow: Int?

    let config: AppConfig
    private let auth: GoogleAuth
    private let sheets: SheetsClient
    private let defaults = UserDefaults.standard

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

    // MARK: - Lifecycle

    func start() async {
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
        editing = nil
        ledger = Ledger()
        workoutPath = []
        historyPath = []
        phase = .signedOut
    }

    func initialLoad() async {
        phase = .loading
        do {
            try await loadAll()
            pickRoutine()
            phase = .ready
            restoreRest()
        } catch {
            if isAuthError(error) {
                signInError = error.localizedDescription
                phase = .signedOut
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func reload() async {
        if let message = await perform("Recarregando…", write: false, {
            try await self.loadAll()
            self.pickRoutine()
        }) {
            show(message, error: true)
        }
    }

    private func loadAll() async throws {
        let plan = try await sheets.values("Rotinas!A1:I")
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

    // MARK: - Selection

    func selectRoutine(_ value: String) {
        routine = value
        defaults.set(value, forKey: "treino")
    }

    func selectDay(_ value: String) {
        day = value
        if phase == .ready { pickRoutine() }
    }

    private func pickRoutine() {
        if let today = ledger.rows.first(where: { $0.day == day && ledger.routines.contains($0.routine) }) {
            routine = today.routine
            return
        }
        if let routine, ledger.routines.contains(routine) { return }
        let saved = defaults.string(forKey: "treino")
        routine = saved.flatMap { ledger.routines.contains($0) ? $0 : nil } ?? ledger.routines.first
    }

    func openForEditing(_ session: Session) {
        day = session.day
        routine = session.routine
        workoutPath = []
        tab = .workout
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
            self.defaults.set(Date().timeIntervalSince1970, forKey: self.startKey(self.day, routine))
        }
        if let error { show(error, error: true); return }
        show(alreadyThere ? "Esse treino já estava na planilha." : "Treino montado. Toque numa série para registrar.")
    }

    func edit(_ x: SetRow) {
        guard busy == nil else { return }
        let last = ledger.lastSet(for: x)
        let load = x.load ?? last?.load
        let unit = ledger.unit(of: x.exercise)
        let rest = (x.rest ?? x.pendingRest).map { Fmt.duration(Double($0)) } ?? ""
        editing = SetDraft(
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

    /// Returns an error to show in the editor, or nil once the editor can close.
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
        RestAlerts.requestPermission()

        var conflict = false
        var message = ""
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

            let restChanged = restProvided && newRest != x.rest
            if restChanged {
                let cell = newRest.map { OutCell.number(Double($0) / 86400) } ?? .blank
                try await self.sheets.update("Registro!P\(x.row)", [[cell]])
                self.mutate(x.row) { y in y.rest = newRest; y.pendingRest = nil }
            }

            let unitChanged = !clear && d.unit != self.ledger.unit(of: x.exercise)
            if unitChanged { try await self.setUnit(x.exercise, d.unit) }

            self.editing = nil
            if kindChanged { self.ledger.renumber() }

            guard let saved = self.ledger.row(x.row) else { return }
            if clear {
                message = "Série limpa."
            } else {
                var parts = ["Série salva"]
                if let delta = self.ledger.delta(saved, self.ledger.lastSet(for: saved)) {
                    parts.append(delta.isUp ? "+\(Fmt.n1(delta.value)) no 1RM" : delta.isDown ? "−\(Fmt.n1(-delta.value)) no 1RM" : "igual à última")
                }
                if restChanged { parts.append(newRest.map { "descanso \(Fmt.duration(Double($0)))" } ?? "descanso apagado") }
                if unitChanged { parts.append("\(x.exercise) agora em \(d.unit.rawValue)") }
                message = parts.joined(separator: " · ") + "."
            }

            if !clear && !wasDone {
                self.startRest(after: saved)
                let key = self.startKey(saved.day ?? self.day, saved.routine)
                if self.defaults.object(forKey: key) == nil {
                    self.defaults.set(Date().timeIntervalSince1970 - 60, forKey: key)
                }
            }
            if clear && self.rest?.row == x.row { self.dismissRest() }
        }
        if conflict {
            editing = nil
            show("A planilha mudou desde que você abriu o app. Confira a série e salve de novo.", error: true)
            return nil
        }
        if let error { return error }
        show(message)
        return nil
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
            try await self.sheets.update("Registro!A\(last.row + 1):F\(last.row + 1)", [[.blank, .blank, .blank, .blank, .blank, .number(Double(last.reps ?? 10))]])
            try await self.loadRegistro()
        }
        if conflict { show("A planilha mudou. Confira e toque em Adicionar série de novo.", error: true); return }
        if let error { show(error, error: true); return }
        if let next = ledger.row(last.row + 1) { edit(next) }
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
            if let rest = self.rest {
                if rest.row == x.row {
                    self.dismissRest()
                } else if rest.row > x.row {
                    self.rest?.row -= 1
                    self.saveRest()
                }
            }
            self.editing = nil
            try await self.loadRegistro()
        }
        if conflict {
            editing = nil
            show("A planilha mudou desde que você abriu o app. Confira e tente de novo.", error: true)
            return nil
        }
        if let error { return error }
        show(endsChain ? "Série removida. A série anterior voltou a ser normal." : "Série removida.")
        return nil
    }

    private func setUnit(_ exercise: String, _ unit: WeightUnit) async throws {
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
        let started = defaults.double(forKey: startKey(z.day, z.routine))
        guard started > 0 else { return nil }
        let minutes = Int(((Date().timeIntervalSince1970 - started) / 60).rounded())
        return minutes > 0 && minutes < 300 ? minutes : nil
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
        defaults.removeObject(forKey: startKey(z.day, z.routine))
        tab = .history
        historyPath = [z.key]
        show("Treino finalizado · \(Fmt.minutes(minutes)).")
        return nil
    }

    // MARK: - Rest timer

    private func startRest(after x: SetRow) {
        let target = SetKind.chainRest(x.kind) ?? ledger.restTarget(exercise: x.exercise, routine: routine)
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
    private func perform(_ label: String, write: Bool, _ operation: () async throws -> Void) async -> String? {
        guard busy == nil else { return "Espere a operação em andamento terminar." }
        busy = label
        defer { busy = nil }
        do {
            try await operation()
            return nil
        } catch {
            return describe(error, write: write)
        }
    }

    private func describe(_ error: Error, write: Bool) -> String {
        if isAuthError(error) {
            editing = nil
            addingExercise = false
            finishing = false
            signInError = "O acesso ao Google expirou. Entre de novo."
            phase = .signedOut
            return signInError ?? ""
        }
        if write, let e = error as? SheetsError, e.isUncertain {
            return "Não sei se gravou. Puxe a lista para recarregar e confira antes de salvar de novo."
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
