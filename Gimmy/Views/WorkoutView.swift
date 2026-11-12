import SwiftUI

/// Workout screen: progress, the open exercise with its quick-entry card, the other exercises compact.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var restEditing: SetRow?
    @State private var restText = ""
    @State private var removing: SetRow?

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.workoutPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        WorkoutControls()
                        content
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.xl)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.focusedGroup?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.smooth) { proxy.scrollTo("g\(id)", anchor: .top) }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(model.routine ?? "Treino")
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MoreMenu() }
            }
            .dismissKeyboardToolbar()
            .refreshable { await model.reload() }
            .navigationDestination(for: String.self) { key in
                SessionDetailView(key: key, allowsEditing: false)
            }
            .safeAreaInset(edge: .bottom) { RestTimerBar() }
        }
        .sheet(item: $model.entry) { _ in SetEditorSheet() }
        .sheet(isPresented: $model.addingExercise) { AddExerciseSheet() }
        .sheet(isPresented: $model.finishing) { FinishSheet() }
        .alert("Descanso depois desta série", isPresented: Binding(
            get: { restEditing != nil },
            set: { if !$0 { restEditing = nil } }
        )) {
            TextField("min:seg, ex. 1:30", text: $restText)
                .keyboardType(.numbersAndPunctuation)
            Button("Salvar") {
                if let row = restEditing { saveRest(row) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deixe vazio para apagar.")
        }
        .confirmationDialog("Remover esta série?", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { row in
            Button("Remover série", role: .destructive) {
                Task {
                    if let error = await model.remove(model.draft(for: row)) { model.show(error, error: true) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("A série sai do treino e da planilha, e as seguintes deste exercício são renumeradas. Para só apagar a carga e manter a série no lugar, use Limpar série.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.ledger.routines.isEmpty {
            NoticeCard(
                title: "Nenhuma rotina",
                message: "Cadastre as rotinas na aba Rotinas da planilha e puxe a tela para recarregar.",
                systemImage: "list.bullet.rectangle"
            )
        } else if model.currentRows.isEmpty {
            StartCard()
        } else {
            session
        }
    }

    @ViewBuilder
    private var session: some View {
        let rows = model.currentRows
        let groups = model.ledger.groups(rows)
        let focused = model.focusedGroup
        let focusedIndex = groups.firstIndex { $0.id == focused?.id }

        ProgressHeader(rows: rows)

        if let minutes = rows.first?.duration, let first = rows.first, let day = first.day {
            NavigationLink(value: "\(day)|\(first.routine)") {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.statusSuccess)
                    Text("Treino finalizado · \(Fmt.minutes(minutes))")
                        .font(AppFont.bodyBold)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("Ver resumo").font(AppFont.caption).foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textMuted)
                }
                .appCard(padding: 14, radius: Radius.lg)
            }
            .buttonStyle(.plain)
        }

        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if group.id == focused?.id {
                ExerciseCard(
                    group: group,
                    onEditRest: { row in
                        restText = row.rest.map { Fmt.duration(Double($0)) } ?? ""
                        restEditing = row
                    },
                    onRemove: { removing = $0 }
                )
                .id("g\(group.id)")
            } else {
                CompactExerciseCard(group: group, isNext: focusedIndex.map { index == $0 + 1 } ?? false)
                    .id("g\(group.id)")
            }
        }

        Button {
            model.addingExercise = true
        } label: {
            Label("Adicionar exercício", systemImage: "plus")
        }
        .buttonStyle(SecondaryButtonStyle(height: 44))
        .disabled(model.busy != nil)

        if rows.contains(where: \.isDone) {
            let finished = rows.first?.duration != nil
            Button {
                model.finishing = true
            } label: {
                Label(finished ? "Editar resumo do treino" : "Finalizar sessão de treino", systemImage: "flag.fill")
            }
            .buttonStyle(SecondaryButtonStyle(height: 48, foreground: .textSecondary, background: .appSurfaceLow))
            .disabled(model.busy != nil)
        }
    }

    private func saveRest(_ row: SetRow) {
        var draft = model.draft(for: row)
        draft.rest = restText
        Task {
            if let error = await model.save(draft, clear: false) { model.show(error, error: true) }
        }
    }
}

// MARK: - Header

/// Routine and date pickers.
private struct WorkoutControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
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
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet").font(.system(size: 12, weight: .semibold))
                    Text("Trocar treino")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, Spacing.sm)
                .frame(height: 36)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.appBorderDefault, lineWidth: 1))
            }
            .disabled(model.busy != nil || model.ledger.routines.isEmpty)

            Spacer()

            DatePicker(
                "Data",
                selection: Binding(
                    get: { DayKey.date(model.day) ?? Date() },
                    set: { model.selectDay(DayKey.from($0)) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}

/// "X de Y séries concluídas" and volume, over a thin progress bar.
private struct ProgressHeader: View {
    @Environment(AppModel.self) private var model
    let rows: [SetRow]

    var body: some View {
        let series = rows.filter { !$0.serie.contains(".") }
        let doneSeries = series.filter(\.isDone).count
        let fraction = rows.isEmpty ? 0 : Double(rows.filter(\.isDone).count) / Double(rows.count)
        let volume = model.ledger.volume(rows)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.busy ?? "\(doneSeries) de \(series.count) séries concluídas")
                    .foregroundStyle(model.busy == nil ? Color.textSecondary : Color.linearBlue)
                Spacer()
                Text("\(Fmt.n0(volume)) kg levantados")
                    .foregroundStyle(Color.textSecondary)
            }
            .font(AppFont.caption)
            .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appSurfaceHigh)
                    Capsule()
                        .fill(Color.linearBlue)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            .animation(.smooth, value: fraction)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Exercise cards

/// The open exercise: every set, actions per set, add a set.
private struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    let group: ExerciseGroup
    let onEditRest: (SetRow) -> Void
    let onRemove: (SetRow) -> Void

    var body: some View {
        let ledger = model.ledger
        let sets = group.rows.map { WorkoutSet(row: $0, ledger: ledger) }

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.linearBlue)
                    Text(group.exercise)
                        .font(AppFont.titleLarge)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(lastTime(ledger))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                ExerciseChips(status: ledger.status(group, day: model.day), record: ledger.isRecord(group, day: model.day))
            }

            Divider().overlay(Color.appBorder)

            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    SetRowView(set: set, isSelected: model.entry?.row.row == set.row.row || model.highlightedRow == set.row.row) {
                        model.select(set.row)
                    }
                    .id(set.row.row)
                    .contextMenu {
                        SetActions(row: set.row, onEditRest: onEditRest, onRemove: onRemove)
                    }
                    if index < sets.count - 1 {
                        Divider().overlay(Color.appBorder.opacity(0.4))
                    }
                }
            }

            Button {
                Task { await model.addSet(to: group) }
            } label: {
                Label("Adicionar série", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.busy != nil)
        }
        .appCard()
    }

    private func lastTime(_ ledger: Ledger) -> String {
        guard let previous = ledger.previousDay(exercise: group.exercise, before: model.day) else {
            return "Primeira vez neste exercício"
        }
        let sets = ledger.sets(exercise: group.exercise, day: previous).filter { !$0.isWarmup }
        return "Última: \(Fmt.shortDay(previous)) · " + sets.map { Fmt.set($0.load, $0.reps) }.joined(separator: "  ·  ")
    }
}

/// Other exercises in the workout, one line each. Tap to open.
private struct CompactExerciseCard: View {
    @Environment(AppModel.self) private var model
    let group: ExerciseGroup
    let isNext: Bool

    var body: some View {
        let done = group.rows.filter(\.isDone).count
        let total = group.rows.filter { !$0.serie.contains(".") }.count
        let status = model.ledger.status(group, day: model.day)
        let complete = done == group.rows.count

        Button {
            withAnimation(.smooth) { model.focus(group) }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: complete ? "checkmark" : done > 0 ? "circle.lefthalf.filled" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(complete ? Color.statusSuccess : Color.textMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.exercise)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(done: done, total: total, complete: complete, status: status))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .appCard(padding: 14, radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
    }

    private func subtitle(done: Int, total: Int, complete: Bool, status: ExerciseStatus?) -> String {
        let count = "\(total) \(total == 1 ? "série" : "séries")"
        if complete { return status.map { "\(count) · \($0.text)" } ?? count }
        if done > 0 { return "\(done) de \(group.rows.count) registradas" }
        return "\(count) planejadas" + (isNext ? " · Próximo" : "")
    }
}

// MARK: - Set actions

/// Type, repeat last, rest, clear and remove for one set, in its long-press menu.
private struct SetActions: View {
    @Environment(AppModel.self) private var model
    let row: SetRow
    let onEditRest: (SetRow) -> Void
    let onRemove: (SetRow) -> Void

    var body: some View {
        let last = model.ledger.lastSet(for: row)
        let currentKind = model.entry?.row.row == row.row ? (model.entry?.kind ?? row.kind) : row.kind

        Section("Série \(row.serie.isEmpty ? "•" : row.serie)") {
            Picker(selection: Binding(
                get: { SetType(kind: currentKind) },
                set: { type in
                    model.select(row)
                    model.entry?.kind = type.sheetValue
                }
            )) {
                ForEach(SetType.allCases) { type in
                    Text(type.title).tag(type)
                }
            } label: {
                Label("Tipo", systemImage: "tag")
            }
            .pickerStyle(.menu)

            if let last {
                Button {
                    model.select(row)
                    model.entry?.load = Fmt.loadInput(last.load)
                    model.entry?.reps = String(last.reps ?? 0)
                } label: {
                    Label("Repetir a última: \(Fmt.set(last.load, last.reps))", systemImage: "arrow.uturn.backward")
                }
            }

            if row.isDone {
                Button {
                    onEditRest(row)
                } label: {
                    Label("Descanso…", systemImage: "timer")
                }
            }
        }

        Section {
            if row.isDone {
                Button(role: .destructive) {
                    Task {
                        if let error = await model.save(model.draft(for: row), clear: true) { model.show(error, error: true) }
                    }
                } label: {
                    Label("Limpar série", systemImage: "eraser")
                }
            }
            Button(role: .destructive) {
                onRemove(row)
            } label: {
                Label("Remover série", systemImage: "trash")
            }
        }
    }
}

// MARK: - Start and notices

/// Before the workout exists in the sheet: what will be created, and the button that creates it.
private struct StartCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let routine = model.routine {
            let template = model.ledger.template(routine: routine, day: model.day)
            if template.rows.isEmpty {
                NoticeCard(title: "Rotina vazia", message: "Não achei exercícios para \(routine) na aba Rotinas.", systemImage: "list.bullet.rectangle")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Fmt.weekday(model.day)), \(Fmt.shortDay(model.day))")
                            .captionLabel()
                        Text(template.previousDay.map { "Mesmos exercícios, séries e reps do treino de \(Fmt.shortDay($0)). As cargas você preenche na hora." }
                             ?? "Montado a partir da rotina planejada. As cargas você preenche na hora.")
                            .font(AppFont.body)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(spacing: 0) {
                        let items = model.ledger.plannedExercises(template)
                        ForEach(items) { item in
                            HStack {
                                Text(item.exercise)
                                    .font(AppFont.body)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text("\(item.sets) \(item.sets == 1 ? "série" : "séries")")
                                    .font(AppFont.number(13, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, 10)
                            if item.id != items.last?.id {
                                Divider().overlay(Color.appBorder.opacity(0.4))
                            }
                        }
                    }

                    Button {
                        Task { await model.startSession() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.busy != nil { ProgressView().tint(.white) }
                            Text(model.busy ?? "Começar treino")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.busy != nil)
                }
                .appCard()
            }
        }
    }
}

struct NoticeCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color.textMuted)
            Text(title)
                .font(AppFont.titleMedium)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: Spacing.xl)
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
