import SwiftUI

/// Configurar tab: the routines (treinos), grouped by whether they are in force today.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.setupPath) {
            content
                .background(Color.appBackground)
                .navigationTitle("Treinos")
                .toolbarBackground(Color.appBackground, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { creating = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Novo treino")
                            .disabled(model.busy != nil)
                    }
                }
                .refreshable { await model.reload() }
                .navigationDestination(for: PlanRoute.self) { route in
                    switch route {
                    case .routine(let id):
                        RoutineDetailView(id: id)
                    case .exercise(let id, let exercise):
                        ExercisePlanView(versionID: id, exercise: exercise)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) { RestTimerBar() }
        .sheet(isPresented: $creating) { NewRoutineSheet() }
    }

    @ViewBuilder
    private var content: some View {
        let today = DayKey.from(Date())
        let versions = model.ledger.versions
        if versions.isEmpty {
            ContentUnavailableView {
                Label("Nenhum treino", systemImage: "list.bullet.clipboard")
            } description: {
                Text("Toque em + para criar um treino e depois adicione os exercícios e as séries.")
            }
        } else {
            List {
                section("Vigentes", versions.filter { $0.status(today: today) == .current },
                        empty: "Nenhum treino vale hoje. Crie um ou ajuste a vigência de um encerrado.")
                section("Programados", versions.filter { $0.status(today: today) == .upcoming }
                    .sorted { ($0.start ?? "") < ($1.start ?? "") })
                section("Encerrados", versions.filter { $0.status(today: today) == .ended }
                    .sorted { ($0.end ?? "") > ($1.end ?? "") })
            }
            .listStyle(.insetGrouped)
            .appListStyle()
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [RoutineVersion], empty: String? = nil) -> some View {
        if !list.isEmpty || empty != nil {
            Section(title) {
                if list.isEmpty, let empty {
                    Text(empty)
                        .font(AppFont.body)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(list) { v in
                    NavigationLink(value: PlanRoute.routine(v.id)) {
                        RoutineRow(version: v)
                    }
                    .accessibilityIdentifier("routine.\(v.name)")
                }
            }
            .listRowBackground(Color.appSurface)
        }
    }
}

private struct RoutineRow: View {
    @Environment(AppModel.self) private var model
    let version: RoutineVersion

    var body: some View {
        let count = model.ledger.items(of: version).count
        VStack(alignment: .leading, spacing: 4) {
            Text(version.name)
                .font(AppFont.titleMedium)
                .foregroundStyle(Color.textPrimary)
            Text("\(Fmt.validity(version.start, version.end)) · \(count) \(count == 1 ? "exercício" : "exercícios")")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - New routine

private struct NewRoutineSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var error: String?

    private var datesFooter: String {
        let dates = hasEnd
            ? "Depois do fim, o treino sai do seletor da tela Treino."
            : "Sem data de fim, é um treino atual: aparece no seletor da tela Treino a partir do início."
        return dates + " Se já houver um treino de mesmo nome valendo nessas datas, ele termina na véspera do início deste."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome, por exemplo Costas", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    DatePicker("Início", selection: $start, displayedComponents: .date)
                    Toggle("Data de fim", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Fim", selection: $end, in: start..., displayedComponents: .date)
                    }
                } header: {
                    Text("Vigência")
                } footer: {
                    Text(datesFooter)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.statusDanger)
                    }
                }
            }
            .appListStyle()
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .navigationTitle("Novo treino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(model.busy != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "Criar treino", busy: model.busy) {
                    Task {
                        error = await model.createRoutine(name: name, start: DayKey.from(start), end: hasEnd ? DayKey.from(end) : nil)
                        if error == nil { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.busy != nil)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Routine

/// A routine's name, dates and exercises.
struct RoutineDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String

    @State private var name = ""
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var loadedID: String?
    @State private var error: String?
    @State private var adding = false
    @State private var confirmingDelete = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if let v = model.ledger.version(id: id) {
                form(v)
            } else {
                ContentUnavailableView("Treino não encontrado", systemImage: "questionmark.circle",
                                       description: Text("Ele pode ter mudado na planilha. Volte e abra de novo."))
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var values: (name: String, start: String?, end: String?) {
        (name.trimmingCharacters(in: .whitespacesAndNewlines), hasStart ? DayKey.from(start) : nil, hasEnd ? DayKey.from(end) : nil)
    }

    private func isChanged(_ v: RoutineVersion) -> Bool {
        guard loadedID == v.id else { return false }
        let x = values
        return x.name != v.name || x.start != v.start || x.end != v.end
    }

    private func form(_ v: RoutineVersion) -> some View {
        let items = model.ledger.items(of: v)
        let locked = !model.ledger.sessionDays(of: v).isEmpty
        let changed = isChanged(v)
        let datesNote = hasEnd ? "Depois do fim, o treino sai do seletor da tela Treino." : "Sem data de fim: é um treino atual."
        let nameNote = locked ? " O nome fica fixo porque já há treinos registrados com ele." : ""

        return List {
            Section {
                TextField("Nome", text: $name)
                    .textInputAutocapitalization(.words)
                    .disabled(locked)
                    .foregroundStyle(locked ? Color.textSecondary : Color.textPrimary)
                Toggle("Data de início", isOn: $hasStart.animation())
                if hasStart {
                    DatePicker("Início", selection: $start, displayedComponents: .date)
                }
                Toggle("Data de fim", isOn: $hasEnd.animation())
                if hasEnd {
                    DatePicker("Fim", selection: $end, displayedComponents: .date)
                }
            } header: {
                Text("Nome e vigência")
            } footer: {
                Text(datesNote + nameNote)
            }
            .listRowBackground(Color.appSurface)

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.statusDanger)
                }
                .listRowBackground(Color.appSurface)
            }

            Section {
                ForEach(items, id: \.row) { item in
                    NavigationLink(value: PlanRoute.exercise(routine: v.id, exercise: item.exercise)) {
                        PlanItemRow(item: item)
                    }
                    .accessibilityIdentifier("planItem.\(item.exercise)")
                }
                .onMove { from, to in
                    var list = items
                    list.move(fromOffsets: from, toOffset: to)
                    let ordered = list
                    Task { error = await model.reorderPlan(ordered, in: v) }
                }
                .onDelete { offsets in
                    guard let i = offsets.first, i < items.count else { return }
                    let item = items[i]
                    Task { error = await model.removePlanItem(item, from: v) }
                }
                Button {
                    adding = true
                } label: {
                    Label("Adicionar exercício", systemImage: "plus")
                }
                .disabled(model.busy != nil)
            } header: {
                Text("Exercícios")
            } footer: {
                if items.count > 1 {
                    Text("Toque em Reordenar para arrastar. Deslize um exercício para a esquerda para tirá-lo do treino.")
                }
            }
            .listRowBackground(Color.appSurface)

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Apagar treino", systemImage: "trash")
                        .foregroundStyle(Color.statusDanger)
                }
                .disabled(model.busy != nil)
            } footer: {
                Text("Os treinos já registrados continuam no histórico.")
            }
            .listRowBackground(Color.appSurface)
        }
        .listStyle(.insetGrouped)
        .appListStyle()
        .environment(\.editMode, $editMode)
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .navigationTitle(v.name)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            if changed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar") { load(v) }
                }
            } else if items.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "OK" : "Reordenar") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .disabled(model.busy != nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if changed {
                BottomActionButton(title: "Salvar nome e vigência", busy: model.busy) { save(v) }
            }
        }
        .onAppear { if loadedID != v.id { load(v) } }
        .sheet(isPresented: $adding) { AddPlanExerciseSheet(version: v) }
        .confirmationDialog("Apagar \(v.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Apagar treino", role: .destructive) {
                Task { error = await model.deleteRoutine(v) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os exercícios e as séries deste treino saem da aba Rotinas. Os treinos já registrados continuam no histórico.")
        }
    }

    private func load(_ v: RoutineVersion) {
        name = v.name
        hasStart = v.start != nil
        start = v.start.flatMap(DayKey.date) ?? Date()
        hasEnd = v.end != nil
        end = v.end.flatMap(DayKey.date) ?? Date()
        loadedID = v.id
        error = nil
    }

    private func save(_ v: RoutineVersion) {
        let x = values
        Task {
            error = await model.updateRoutine(v, name: x.name, start: x.start, end: x.end)
            if error == nil, let updated = model.ledger.version(id: RoutineVersion.id(x.name, x.start)) { load(updated) }
        }
    }
}

/// An exercise of a routine: name, one dot per set in its type's color, the reps.
private struct PlanItemRow: View {
    @Environment(AppModel.self) private var model
    let item: PlanItem

    var body: some View {
        let planned = model.ledger.plannedSets(item, before: DayKey.from(Date()))
        let kinds = planned.sets.map(\.kind)
        let series = Series.count(kinds)

        VStack(alignment: .leading, spacing: 6) {
            Text(item.exercise)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: Spacing.xs) {
                HStack(spacing: 3) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                        Circle().fill(SetType(kind: kind).tintColor).frame(width: 7, height: 7)
                    }
                }
                Text("\(series) \(series == 1 ? "série" : "séries") · \(planned.sets.map { String($0.reps) }.joined(separator: "-"))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if planned.source != .configured {
                Text("Séries ainda não configuradas")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct AddPlanExerciseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let version: RoutineVersion
    @State private var choice = ""
    @State private var custom = ""
    @State private var unit: WeightUnit = .kg
    @State private var error: String?

    private static let newExercise = "__novo"

    var body: some View {
        let taken = Set(model.ledger.items(of: version).map(\.exercise))
        NavigationStack {
            Form {
                Section {
                    Picker("Exercício", selection: $choice) {
                        Text("Escolha…").tag("")
                        ForEach(model.ledger.exercises.filter { !taken.contains($0) }, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        Text("Outro (novo)…").tag(Self.newExercise)
                    }
                    .pickerStyle(.navigationLink)
                    if choice == Self.newExercise {
                        TextField("Nome do exercício novo", text: $custom)
                            .textInputAutocapitalization(.words)
                    }
                } footer: {
                    Text("Entra com 3 séries normais de 10 reps. Em seguida você ajusta as séries, os tipos e as reps.")
                }

                Section("Unidade") {
                    Picker("Unidade", selection: $unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.statusDanger)
                    }
                }
            }
            .appListStyle()
            .navigationTitle("Adicionar a \(version.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(model.busy != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "Adicionar exercício", busy: model.busy) {
                    let name = choice == Self.newExercise ? custom : choice
                    Task {
                        error = await model.addPlanExercise(to: version, name: name, unit: unit)
                        if error == nil { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.busy != nil)
        .preferredColorScheme(.dark)
        .onChange(of: choice) { _, name in
            error = nil
            if !name.isEmpty && name != Self.newExercise { unit = model.ledger.unit(of: name) }
        }
    }
}

// MARK: - Exercise

/// One exercise of a routine: its sets (type and reps), planned rest, unit and notes.
struct ExercisePlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let versionID: String
    let exercise: String

    private struct Snapshot: Equatable {
        var sets: [PlanSet]
        var notes: String
        var rest: String
        var unit: WeightUnit
    }

    @State private var sets: [PlanSet] = []
    @State private var notes = ""
    @State private var rest = ""
    @State private var unit: WeightUnit = .kg
    @State private var initial: Snapshot?
    @State private var error: String?
    @State private var editMode: EditMode = .inactive
    @State private var confirmingRemoval = false

    var body: some View {
        Group {
            if let v = model.ledger.version(id: versionID),
               let item = model.ledger.items(of: v).first(where: { $0.exercise == exercise }) {
                editor(v, item)
            } else {
                ContentUnavailableView("Exercício não encontrado", systemImage: "questionmark.circle",
                                       description: Text("Ele pode ter mudado na planilha. Volte e abra de novo."))
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var current: Snapshot { Snapshot(sets: sets, notes: notes, rest: rest, unit: unit) }

    private func editor(_ v: RoutineVersion, _ item: PlanItem) -> some View {
        let source = model.ledger.plannedSets(item, before: DayKey.from(Date())).source
        let changed = initial != nil && initial != current
        let labels = Series.labels(sets.map(\.kind))

        return List {
            Section {
                ForEach($sets) { $set in
                    let i = sets.firstIndex { $0.id == set.id } ?? 0
                    PlanSetRow(label: i < labels.count ? labels[i] : "", set: $set)
                }
                .onDelete { sets.remove(atOffsets: $0) }
                .onMove { sets.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    sets.append(PlanSet(kind: SetKind.normal, reps: sets.last?.reps ?? 10))
                } label: {
                    Label("Adicionar série", systemImage: "plus")
                }
                .disabled(sets.count >= PlanSets.maxSets)
            } header: {
                Text("Séries")
            } footer: {
                Text(setsFooter(source))
            }
            .listRowBackground(Color.appSurface)

            Section {
                HStack(spacing: Spacing.xs) {
                    Button { bumpRest(item, -15) } label: { Image(systemName: "minus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Menos 15 segundos")
                    TextField("1:30", text: $rest)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(AppFont.number(22))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Descanso alvo")
                    Button { bumpRest(item, 15) } label: { Image(systemName: "plus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Mais 15 segundos")
                }
            } header: {
                Text("Descanso alvo (min:seg)")
            } footer: {
                Text("Digite só números: 200 vira 2:00. Vazio usa 1:30. Drop e rest-pause continuam com 10 s e 15 s.")
            }
            .listRowBackground(Color.appSurface)

            Section("Unidade") {
                Picker("Unidade", selection: $unit) {
                    ForEach(WeightUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.appSurface)

            Section("Notas") {
                TextField("Por exemplo: 3ª com drop até a falha", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            .listRowBackground(Color.appSurface)

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.statusDanger)
                }
                .listRowBackground(Color.appSurface)
            }

            Section {
                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label("Tirar do treino", systemImage: "trash")
                        .foregroundStyle(Color.statusDanger)
                }
                .disabled(model.busy != nil)
            }
            .listRowBackground(Color.appSurface)
        }
        .listStyle(.insetGrouped)
        .appListStyle()
        .environment(\.editMode, $editMode)
        .navigationTitle(exercise)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            if changed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar") { dismiss() }
                }
            }
            if sets.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "OK" : "Reordenar") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
        }
        .dismissKeyboardToolbar()
        .safeAreaInset(edge: .bottom) {
            if changed || source != .configured {
                BottomActionButton(title: "Salvar exercício", busy: model.busy) { save(item) }
            }
        }
        .onAppear { if initial == nil { load(item) } }
        .confirmationDialog("Tirar \(exercise) de \(v.name)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Tirar do treino", role: .destructive) {
                Task { error = await model.removePlanItem(item, from: v) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ele sai só da configuração. As séries já registradas continuam no histórico.")
        }
    }

    private func setsFooter(_ source: Ledger.PlanSource) -> String {
        switch source {
        case .configured:
            return "Ao começar o treino, o app copia estas séries com tipo e reps. As cargas você preenche na hora."
        case .lastSession(let day):
            return "Ainda não configurado: estas são as séries do treino de \(Fmt.shortDay(day)). Salve para fixá-las."
        case .sheet:
            return "Ainda não configurado: montado pelas colunas Séries e Reps da planilha. Salve para fixar."
        }
    }

    private func load(_ item: PlanItem) {
        let snapshot = Snapshot(
            sets: model.ledger.plannedSets(item, before: DayKey.from(Date())).sets,
            notes: item.notes,
            rest: item.rest.map { Fmt.duration($0) } ?? "",
            unit: model.ledger.unit(of: item.exercise)
        )
        sets = snapshot.sets
        notes = snapshot.notes
        rest = snapshot.rest
        unit = snapshot.unit
        initial = snapshot
    }

    private func bumpRest(_ item: PlanItem, _ delta: Int) {
        let base: Int
        if case .seconds(let s) = RestInput.parse(rest) { base = s } else { base = Int(item.rest ?? 90) }
        rest = Fmt.duration(Double(max(15, base + delta)))
    }

    private func save(_ item: PlanItem) {
        let snapshot = current
        Task {
            error = await model.savePlanItem(item, sets: snapshot.sets, notes: snapshot.notes, rest: snapshot.rest, unit: snapshot.unit)
            if error == nil {
                initial = snapshot
                dismiss()
            }
        }
    }
}

/// A planned set: badge, type menu, reps stepper.
private struct PlanSetRow: View {
    let label: String
    @Binding var set: PlanSet

    var body: some View {
        let type = SetType(kind: set.kind)
        HStack(spacing: Spacing.sm) {
            SetBadge(label: label, type: type, filled: false)

            Menu {
                Picker("Tipo", selection: Binding(get: { type }, set: { set.kind = $0.sheetValue })) {
                    ForEach(SetType.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(type.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Tipo da série \(label)")
            .accessibilityValue(type.title)

            Spacer(minLength: 4)

            Button { set.reps = max(1, set.reps - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(StepperButtonStyle())
                .accessibilityLabel("Menos uma rep na série \(label)")
            Text("\(set.reps)")
                .font(AppFont.number(20))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 30)
                .accessibilityLabel("\(set.reps) reps")
            Button { set.reps = min(100, set.reps + 1) } label: { Image(systemName: "plus") }
                .buttonStyle(StepperButtonStyle())
                .accessibilityLabel("Mais uma rep na série \(label)")
        }
    }
}
