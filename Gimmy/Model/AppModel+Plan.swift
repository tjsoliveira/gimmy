import Foundation

/// Screens of the Configurar tab.
enum PlanRoute: Hashable {
    case routine(String)
    case exercise(routine: String, exercise: String)
}

typealias SheetWrite = (range: String, rows: [[OutCell]])

/// A finished workout the app offers to turn into a new routine.
struct NewRoutineOffer: Equatable {
    var session: String
    var routine: String
    var version: String
}

/// Routine setup: the Rotinas tab, one line per exercise of a routine version.
/// Columns D and E hold the sheet's formulas and are never written.
extension AppModel {
    private static let conflictMessage = "A aba Rotinas mudou desde que você abriu esta tela. Confira e tente de novo."

    private func planSheetID() async throws -> Int {
        if let id = tabIDs["Rotinas"] { return id }
        tabIDs = try await sheets.sheetIDs()
        guard let id = tabIDs["Rotinas"] else { throw SheetsError(kind: .rejected, message: "Não achei a aba Rotinas na planilha.") }
        return id
    }

    /// Re-reads the Rotinas tab. False if any of `expected` no longer sits on its line.
    private func refreshPlan(expecting expected: [PlanItem]) async throws -> (ok: Bool, headers: [Cell]) {
        let values = try await sheets.values("Rotinas!A1:L")
        ledger.parsePlan(values)
        let ok = expected.allSatisfy { e in
            ledger.plan.contains { $0.row == e.row && $0.routine == e.routine && $0.exercise == e.exercise && $0.start == e.start }
        }
        return (ok, values.first ?? [])
    }

    /// Titles for columns J to L, written the first time the app uses them.
    private func headerWrites(_ headers: [Cell]) -> [SheetWrite] {
        let titles = ["Tipos", "Início", "Fim"]
        let cells: [OutCell] = titles.indices.map { i in Parse.text(headers.at(9 + i)).isEmpty ? .text(titles[i]) : .skip }
        guard cells.contains(where: { if case .skip = $0 { return false } else { return true } }) else { return [] }
        return [("Rotinas!J1:L1", [cells])]
    }

    private static func dateCell(_ day: String?) -> OutCell { day.map { OutCell.text($0) } ?? .blank }

    private func lines(of v: RoutineVersion) -> [PlanItem] { ledger.plan.filter { v.rows.contains($0.row) } }

    private func afterPlanChange() {
        pickRoutine()
        ensureSelection()
    }

    // MARK: Routines

    /// Returns an error to show, or nil once created (the new routine opens).
    func createRoutine(name raw: String, start: String, end: String?) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = RoutineRules.validate(name: name, start: start, end: end, others: ledger.versions) { return problem }
        var problem: String?
        let error = await perform("Criando treino…", write: true) {
            let (_, headers) = try await self.refreshPlan(expecting: [])
            if let p = RoutineRules.validate(name: name, start: start, end: end, others: self.ledger.versions) { problem = p; return }
            let r = self.ledger.planRowCount + 1
            var writes = self.headerWrites(headers)
            writes.append(("Rotinas!A\(r):C\(r)", [[OutCell.literal(name), .blank, .blank]]))
            writes.append(("Rotinas!K\(r):L\(r)", [[Self.dateCell(start), Self.dateCell(end)]]))
            try await self.sheets.update(writes)
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        afterPlanChange()
        setupPath = [.routine(RoutineVersion.id(name, start))]
        show("\(name) criado. Agora adicione os exercícios.")
        return nil
    }

    /// Saves a routine's name and dates on all its lines. Returns an error to show, or nil once saved.
    func updateRoutine(_ v: RoutineVersion, name raw: String, start: String?, end: String?) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = ledger.versions.filter { $0.id != v.id }
        if let problem = RoutineRules.validate(name: name, start: start, end: end, others: others) { return problem }
        if name != v.name && !ledger.sessionDays(of: v).isEmpty {
            return "O nome não pode mudar: já há treinos registrados como \(v.name)."
        }
        var problem: String?
        let error = await perform("Salvando treino…", write: true) {
            let (ok, headers) = try await self.refreshPlan(expecting: self.lines(of: v))
            guard ok else { problem = Self.conflictMessage; return }
            let others = self.ledger.versions.filter { $0.id != v.id }
            if let p = RoutineRules.validate(name: name, start: start, end: end, others: others) { problem = p; return }
            var writes = self.headerWrites(headers)
            for r in v.rows {
                if name != v.name { writes.append(("Rotinas!A\(r)", [[OutCell.literal(name)]])) }
                writes.append(("Rotinas!K\(r):L\(r)", [[Self.dateCell(start), Self.dateCell(end)]]))
            }
            try await self.sheets.update(writes)
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        let newID = RoutineVersion.id(name, start)
        setupPath = setupPath.map { (route: PlanRoute) -> PlanRoute in
            switch route {
            case .routine(let id) where id == v.id: return .routine(newID)
            case .exercise(let id, let exercise) where id == v.id: return .exercise(routine: newID, exercise: exercise)
            default: return route
            }
        }
        if name != v.name && routine == v.name {
            routine = name
            defaults.set(name, forKey: "treino")
        }
        afterPlanChange()
        show("\(name) salvo · \(Fmt.validity(start, end).lowercased()).")
        return nil
    }

    /// Deletes all the routine's lines. The Registro tab keeps its history.
    func deleteRoutine(_ v: RoutineVersion) async -> String? {
        var problem: String?
        let error = await perform("Apagando treino…", write: true) {
            let (ok, _) = try await self.refreshPlan(expecting: self.lines(of: v))
            guard ok else { problem = Self.conflictMessage; return }
            try await self.sheets.deleteRows(sheetID: try await self.planSheetID(), rows: v.rows)
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        setupPath = []
        afterPlanChange()
        show("\(v.name) apagado. Os treinos já registrados continuam no histórico.")
        return nil
    }

    /// Makes a new routine from a finished workout: the routine in force ends on the workout's day, and a new
    /// version with the same name, the workout's exercises and sets, starts the day after.
    func acceptNewRoutine(_ offer: NewRoutineOffer) async {
        newRoutineOffer = nil
        guard let session = ledger.session(offer.session), let current = ledger.version(id: offer.version) else {
            show("Não achei o treino para montar a rotina. Recarregue e monte pela aba Configurar.", error: true)
            return
        }
        var planned: [String: NewRoutine.Planned] = [:]
        for item in ledger.items(of: current) where planned[item.exercise] == nil {
            planned[item.exercise] = NewRoutine.Planned(sets: ledger.plannedSets(item, before: session.day).sets,
                                                        notes: item.notes, rest: item.rest)
        }
        let items = NewRoutine.items(session: session.rows, plan: planned)
        let start = DayKey.offset(session.day, by: 1)
        if let error = await replaceRoutine(current, with: items, endingOn: session.day, startingOn: start) {
            show(error, error: true)
            return
        }
        show("Rotina nova de \(current.name) a partir de \(Fmt.fullDay(start)). A anterior ficou em Encerrados.")
    }

    private func replaceRoutine(_ current: RoutineVersion, with items: [NewRoutine.Item],
                                endingOn end: String, startingOn start: String) async -> String? {
        guard !items.isEmpty else { return "O treino não tem exercícios para montar uma rotina." }
        var problem: String?
        let error = await perform("Montando a rotina nova…", write: true) {
            let (ok, headers) = try await self.refreshPlan(expecting: self.lines(of: current))
            guard ok, let fresh = self.ledger.version(id: current.id) else { problem = Self.conflictMessage; return }
            let others = self.ledger.versions.filter { $0.id != fresh.id }
            if let p = RoutineRules.validate(name: fresh.name, start: start, end: nil, others: others) { problem = p; return }
            var writes = self.headerWrites(headers)
            for r in fresh.rows {
                writes.append(("Rotinas!L\(r)", [[Self.dateCell(end)]]))
            }
            let first = self.ledger.planRowCount + 1
            for (i, item) in items.enumerated() {
                let r = first + i
                let cols = PlanSets.columns(item.sets)
                writes.append(("Rotinas!A\(r):C\(r)", [[OutCell.literal(fresh.name), .number(Double(i + 1)), OutCell.literal(item.exercise)]]))
                writes.append(("Rotinas!F\(r):L\(r)", [[
                    .number(Double(cols.series)), OutCell.literal(cols.reps), OutCell.literal(item.notes),
                    item.rest.map { OutCell.number($0) } ?? .blank, .text(cols.kinds), Self.dateCell(start), .blank,
                ]]))
            }
            try await self.sheets.update(writes)
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        afterPlanChange()
        return nil
    }

    // MARK: Exercises

    /// Adds an exercise with 3 normal sets of 10 right after the routine's last line, then opens it.
    func addPlanExercise(to v: RoutineVersion, name raw: String, unit: WeightUnit) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Escolha ou escreva o exercício." }
        if ledger.items(of: v).contains(where: { $0.exercise.caseInsensitiveCompare(name) == .orderedSame }) {
            return "\(name) já está neste treino."
        }
        var problem: String?
        let error = await perform("Adicionando…", write: true) {
            let (ok, headers) = try await self.refreshPlan(expecting: self.lines(of: v))
            guard ok, let current = self.ledger.version(id: v.id) else { problem = Self.conflictMessage; return }
            let items = self.ledger.items(of: current)
            let order = (items.compactMap(\.order).max() ?? Double(items.count)).rounded(.down) + 1
            let sets = (0..<3).map { _ in PlanSet(kind: SetKind.normal, reps: 10) }
            let cols = PlanSets.columns(sets)
            let r: Int
            if let placeholder = self.lines(of: current).first(where: { $0.exercise.isEmpty }) {
                r = placeholder.row
            } else {
                let after = current.rows.max() ?? self.ledger.planRowCount
                try await self.sheets.insertRows(sheetID: try await self.planSheetID(), after: after, count: 1)
                r = after + 1
            }
            var writes = self.headerWrites(headers)
            writes.append(("Rotinas!A\(r):C\(r)", [[OutCell.literal(current.name), .number(order), OutCell.literal(name)]]))
            writes.append(("Rotinas!F\(r):L\(r)", [[
                .number(Double(cols.series)), OutCell.literal(cols.reps), .blank, .blank, .text(cols.kinds),
                Self.dateCell(current.start), Self.dateCell(current.end),
            ]]))
            try await self.sheets.update(writes)
            if !self.ledger.exercises.contains(name) || unit != self.ledger.unit(of: name) {
                try await self.setUnit(name, unit)
            }
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        afterPlanChange()
        setupPath.append(.exercise(routine: v.id, exercise: name))
        return nil
    }

    /// Takes an exercise out of the routine. The routine's last exercise leaves an empty line that keeps the routine.
    func removePlanItem(_ item: PlanItem, from v: RoutineVersion) async -> String? {
        var problem: String?
        let error = await perform("Removendo…", write: true) {
            let (ok, _) = try await self.refreshPlan(expecting: [item])
            guard ok, let current = self.ledger.version(id: v.id) else { problem = Self.conflictMessage; return }
            if current.rows.count > 1 {
                try await self.sheets.deleteRows(sheetID: try await self.planSheetID(), rows: [item.row])
            } else {
                try await self.sheets.update([
                    ("Rotinas!B\(item.row):C\(item.row)", [[OutCell.blank, .blank]]),
                    ("Rotinas!F\(item.row):J\(item.row)", [[OutCell.blank, .blank, .blank, .blank, .blank]]),
                ])
            }
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        setupPath.removeAll { if case .exercise(v.id, item.exercise) = $0 { return true } else { return false } }
        afterPlanChange()
        show("\(item.exercise) saiu do \(v.name).")
        return nil
    }

    /// Rewrites the Ordem column in the given order.
    func reorderPlan(_ items: [PlanItem], in v: RoutineVersion) async -> String? {
        var problem: String?
        let error = await perform("Reordenando…", write: true) {
            let (ok, _) = try await self.refreshPlan(expecting: items)
            guard ok else { problem = Self.conflictMessage; return }
            let writes: [SheetWrite] = items.enumerated().map { i, item in
                ("Rotinas!B\(item.row)", [[OutCell.number(Double(i + 1))]])
            }
            try await self.sheets.update(writes)
            try await self.loadPlan()
        }
        return error ?? problem
    }

    /// Rewrites an exercise's planned sets in a new order (reps in G, types in J; the number of series doesn't change).
    /// Runs inside another `perform`. False when its Rotinas line changed since the app read it.
    func writePlannedOrder(_ item: PlanItem, _ sets: [PlanSet]) async throws -> Bool {
        let (ok, headers) = try await refreshPlan(expecting: [item])
        guard ok, let fresh = ledger.plan.first(where: { $0.row == item.row }),
              PlanSets.configured(kinds: fresh.kinds, reps: fresh.reps) == PlanSets.configured(kinds: item.kinds, reps: item.reps)
        else { return false }
        let cols = PlanSets.columns(sets)
        var writes = headerWrites(headers)
        writes.append(("Rotinas!G\(item.row)", [[OutCell.literal(cols.reps)]]))
        writes.append(("Rotinas!J\(item.row)", [[OutCell.text(cols.kinds)]]))
        try await sheets.update(writes)
        try await loadPlan()
        return true
    }

    /// Saves an exercise's sets, notes, planned rest and unit. Returns an error to show, or nil once saved.
    func savePlanItem(_ item: PlanItem, sets: [PlanSet], notes rawNotes: String, rest restText: String, unit: WeightUnit) async -> String? {
        guard !sets.isEmpty else { return "Deixe pelo menos uma série." }
        guard sets.count <= PlanSets.maxSets else { return "Use até \(PlanSets.maxSets) séries." }
        guard sets.allSatisfy({ (1...100).contains($0.reps) }) else { return "As reps de cada série vão de 1 a 100." }
        let rest: Int?
        switch RestInput.parse(restText) {
        case .empty: rest = nil
        case .seconds(let s) where s > 0 && s <= 3600: rest = s
        default: return "Descanso: use minutos e segundos, por exemplo 1:30."
        }
        let notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        var problem: String?
        let error = await perform("Salvando exercício…", write: true) {
            let (ok, headers) = try await self.refreshPlan(expecting: [item])
            guard ok else { problem = Self.conflictMessage; return }
            let cols = PlanSets.columns(sets)
            var writes = self.headerWrites(headers)
            writes.append(("Rotinas!F\(item.row):J\(item.row)", [[
                .number(Double(cols.series)), OutCell.literal(cols.reps), OutCell.literal(notes),
                rest.map { OutCell.number(Double($0)) } ?? .blank, .text(cols.kinds),
            ]]))
            try await self.sheets.update(writes)
            if unit != self.ledger.unit(of: item.exercise) { try await self.setUnit(item.exercise, unit) }
            try await self.loadPlan()
        }
        if let error { return error }
        if let problem { return problem }
        show("\(item.exercise) salvo · \(Series.count(sets.map(\.kind))) séries.")
        return nil
    }
}
