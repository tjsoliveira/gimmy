import SwiftUI

struct WorkoutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.workoutPath) {
            ScrollViewReader { proxy in
                List {
                    pickers
                    if model.ledger.routines.isEmpty {
                        ContentUnavailableView(
                            "Nenhuma rotina",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Cadastre as rotinas na aba Rotinas da planilha e puxe a lista para recarregar.")
                        )
                    } else if model.currentRows.isEmpty {
                        StartSections()
                    } else {
                        SessionSections()
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: model.highlightedRow) { _, row in
                    guard let row else { return }
                    withAnimation(.smooth) { proxy.scrollTo(row, anchor: .center) }
                }
            }
            .navigationTitle(model.routine ?? "Treino")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MoreMenu() }
            }
            .refreshable { await model.reload() }
            .navigationDestination(for: String.self) { key in
                SessionDetailView(key: key, allowsEditing: false)
            }
            .safeAreaInset(edge: .bottom) { RestTimerBar() }
        }
        .sheet(item: $model.editing) { draft in
            SetEditorSheet(draft: draft)
        }
        .sheet(isPresented: $model.addingExercise) {
            AddExerciseSheet()
        }
        .sheet(isPresented: $model.finishing) {
            FinishSheet()
        }
    }

    private var pickers: some View {
        Section {
            Picker("Treino", selection: Binding(
                get: { model.routine ?? "" },
                set: { model.selectRoutine($0) }
            )) {
                let trained = model.routinesOnDay
                ForEach(model.ledger.routines, id: \.self) { name in
                    if trained.contains(name) {
                        Label(name, systemImage: "checkmark.circle.fill").tag(name)
                    } else {
                        Text(name).tag(name)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(model.busy != nil || model.ledger.routines.isEmpty)

            DatePicker(
                "Data",
                selection: Binding(
                    get: { DayKey.date(model.day) ?? Date() },
                    set: { model.selectDay(DayKey.from($0)) }
                ),
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}

private struct MoreMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.busy != nil {
            ProgressView()
        } else {
            Menu {
                Button("Recarregar da planilha", systemImage: "arrow.clockwise") {
                    Task { await model.reload() }
                }
                if let url = model.config.spreadsheetURL {
                    Link(destination: url) {
                        Label("Abrir a planilha", systemImage: "tablecells")
                    }
                }
                Divider()
                Button("Sair da conta Google", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    model.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Mais opções")
        }
    }
}

/// Before the workout exists in the sheet: what will be created, and the button that creates it.
private struct StartSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let routine = model.routine {
            let template = model.ledger.template(routine: routine, day: model.day)
            if template.rows.isEmpty {
                ContentUnavailableView(
                    "Rotina vazia",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Não achei exercícios para \(routine) na aba Rotinas.")
                )
            } else {
                Section {
                    ForEach(model.ledger.plannedExercises(template)) { item in
                        LabeledContent {
                            Text("\(item.sets) \(item.sets == 1 ? "série" : "séries")")
                                .monospacedDigit()
                        } label: {
                            Text(item.exercise)
                        }
                    }
                } header: {
                    Text("\(routine) · \(Fmt.weekday(model.day)), \(Fmt.shortDay(model.day))")
                } footer: {
                    if let previous = template.previousDay {
                        Text("Mesmos exercícios, séries e reps do treino de \(Fmt.shortDay(previous)). As cargas você preenche na hora.")
                    } else {
                        Text("Montado a partir da rotina planejada. As cargas você preenche na hora.")
                    }
                }

                Section {
                    Button {
                        Task { await model.startSession() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.busy != nil { ProgressView().tint(.white) }
                            Text(model.busy ?? "Começar treino")
                                .font(.condensed(.title3, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.busy != nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

/// The workout in progress: summary, one section per exercise, then add / finish.
private struct SessionSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ledger = model.ledger
        let rows = model.currentRows
        let groups = ledger.groups(rows)
        let finished = rows.first?.duration

        progress(rows: rows)

        if let finished, let first = rows.first, let day = first.day {
            Section {
                NavigationLink(value: "\(day)|\(first.routine)") {
                    Label {
                        Text("Treino finalizado · \(Fmt.minutes(finished))")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }
            }
        }

        ForEach(groups) { group in
            ExerciseSection(group: group)
        }

        Section {
            Button("Adicionar exercício", systemImage: "plus.circle") {
                model.addingExercise = true
            }
            .disabled(model.busy != nil)
        }

        if rows.contains(where: \.isDone) {
            Section {
                Button {
                    model.finishing = true
                } label: {
                    Text(finished == nil ? "Finalizar treino" : "Editar resumo do treino")
                        .font(.condensed(.title3, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.busy != nil)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func progress(rows: [SetRow]) -> some View {
        let ledger = model.ledger
        let series = rows.filter { !$0.serie.contains(".") }
        let doneSeries = series.filter(\.isDone).count
        let fraction = rows.isEmpty ? 0 : Double(rows.filter(\.isDone).count) / Double(rows.count)
        let volume = ledger.volume(rows)
        var line = "\(doneSeries) de \(series.count) séries · \(Fmt.n0(volume)) kg"
        if let routine = model.routine, let previous = ledger.previousSessionDay(routine: routine, before: model.day) {
            line += " · em \(Fmt.shortDay(previous)): \(Fmt.n0(ledger.volume(routine: routine, day: previous))) kg"
        }
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction)
                    .animation(.smooth, value: fraction)
                Text(model.busy ?? line)
                    .font(.subheadline)
                    .foregroundStyle(model.busy == nil ? Color.secondary : Color.accentColor)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ExerciseSection: View {
    @Environment(AppModel.self) private var model
    let group: ExerciseGroup

    var body: some View {
        let ledger = model.ledger
        Section {
            ForEach(group.rows) { row in
                Button {
                    model.edit(row)
                } label: {
                    SetRowContent(row: row)
                }
                .foregroundStyle(.primary)
                .id(row.row)
                .listRowBackground(model.highlightedRow == row.row ? Color.accentColor.opacity(0.15) : nil)
            }
            Button("Adicionar série", systemImage: "plus") {
                Task { await model.addSet(to: group) }
            }
            .disabled(model.busy != nil)
        } header: {
            ExerciseHeader(
                name: group.exercise,
                status: ledger.status(group, day: model.day),
                record: ledger.isRecord(group, day: model.day)
            )
        } footer: {
            Text(lastTime(ledger))
                .monospacedDigit()
        }
    }

    private func lastTime(_ ledger: Ledger) -> String {
        guard let previous = ledger.previousDay(exercise: group.exercise, before: model.day) else {
            return "Primeira vez neste exercício"
        }
        let sets = ledger.sets(exercise: group.exercise, day: previous).filter { !$0.isWarmup }
        return "Última: \(Fmt.shortDay(previous)) · " + sets.map { Fmt.set($0.load, $0.reps) }.joined(separator: "  ·  ")
    }
}
