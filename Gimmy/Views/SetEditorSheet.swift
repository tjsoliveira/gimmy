import SwiftUI

/// Logs one set. Opens on top of the workout; nothing is written until Salvar.
struct SetEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SetDraft
    @State private var error: String?

    init(draft: SetDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        let row = draft.row
        let unit = draft.unit.rawValue
        NavigationStack {
            Form {
                if let last = draft.last {
                    Section {
                        Button {
                            draft.load = Fmt.loadInput(last.load)
                            draft.reps = String(last.reps ?? 0)
                            error = nil
                        } label: {
                            Label("Repetir a última: \(Fmt.n(last.load ?? 0)) \(unit) × \(last.reps ?? 0)", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                Section("Carga (\(unit))") {
                    BigStepper(
                        text: $draft.load,
                        keyboard: .decimalPad,
                        decrementLabel: "Menos \(Fmt.n(draft.step)) \(unit)",
                        incrementLabel: "Mais \(Fmt.n(draft.step)) \(unit)",
                        fieldLabel: "Carga em \(unit)",
                        onDecrement: { bumpLoad(-draft.step) },
                        onIncrement: { bumpLoad(draft.step) }
                    )
                    Picker("Incremento", selection: $draft.step) {
                        ForEach(draft.unit.steps, id: \.self) { step in
                            Text("±\(Fmt.n(step)) \(unit)").tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Reps") {
                    BigStepper(
                        text: $draft.reps,
                        keyboard: .numberPad,
                        decrementLabel: "Menos uma rep",
                        incrementLabel: "Mais uma rep",
                        fieldLabel: "Reps",
                        onDecrement: { bumpReps(-1) },
                        onIncrement: { bumpReps(1) }
                    )
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $draft.kind) {
                        Text("Normal").tag(SetKind.normal)
                        Text("Drop").tag(SetKind.drop)
                        Text("Rest-p.").tag(SetKind.restPause)
                        Text("Falha").tag(SetKind.failure)
                        Text("Aquec.").tag(SetKind.warmup)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Unidade", selection: $draft.unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Unidade do exercício")
                } footer: {
                    if draft.unit != model.ledger.unit(of: row.exercise) {
                        Text("Vale para todo o histórico de \(row.exercise). Grava quando você salvar a série.")
                    }
                }

                if row.isDone {
                    Section("Descanso depois desta série (min:seg)") {
                        BigStepper(
                            text: $draft.rest,
                            keyboard: .numbersAndPunctuation,
                            placeholder: "sem registro",
                            decrementLabel: "Menos 15 segundos",
                            incrementLabel: "Mais 15 segundos",
                            fieldLabel: "Descanso",
                            onDecrement: { bumpRest(-15) },
                            onIncrement: { bumpRest(15) }
                        )
                    }
                }

                Section {
                    preview
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if row.isDone {
                    Section {
                        Button("Limpar série", role: .destructive) {
                            Task { error = await model.save(draft, clear: true) }
                        }
                        .disabled(model.busy != nil)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(model.busy != nil)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(row.exercise)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Série \(row.serie.isEmpty ? "•" : row.serie)" + (draft.kind.isEmpty ? "" : " · \(draft.kind)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .dismissKeyboardToolbar()
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "Salvar série", busy: model.busy) {
                    Task { error = await model.save(draft, clear: false) }
                }
            }
        }
        .interactiveDismissDisabled(model.busy != nil)
        .onChange(of: draft.unit) { _, unit in
            draft.step = unit.defaultStep(for: Parse.number(draft.load))
        }
        .onChange(of: draft.load) { error = nil }
        .onChange(of: draft.reps) { error = nil }
        .onChange(of: draft.rest) { error = nil }
    }

    @ViewBuilder
    private var preview: some View {
        let reps = Int(draft.reps) ?? 0
        if let estimate = OneRM.estimate(Parse.number(draft.load), reps) {
            let previous = draft.last.flatMap { OneRM.estimate($0.load, $0.reps) }
            let change = previous.map { ((estimate - $0) * 10).rounded() / 10 }
            HStack(spacing: 6) {
                Text("1RM est. \(Fmt.n1(estimate)) \(draft.unit.rawValue)")
                    .foregroundStyle(.secondary)
                if let change {
                    if change > 0 {
                        Label("\(Fmt.n1(change)) vs. a última", systemImage: "arrow.up").foregroundStyle(.green)
                    } else if change < 0 {
                        Label("\(Fmt.n1(-change)) vs. a última", systemImage: "arrow.down").foregroundStyle(.red)
                    } else {
                        Text("· igual à última").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.condensed(.headline))
            .monospacedDigit()
            .labelStyle(.titleAndIcon)
        } else {
            Text("Informe carga e reps para ver o 1RM estimado.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func bumpLoad(_ delta: Double) {
        let value = max(0, (((Parse.number(draft.load) ?? 0) + delta) * 100).rounded() / 100)
        draft.load = Fmt.loadInput(value)
    }

    private func bumpReps(_ delta: Int) {
        draft.reps = String(max(1, (Int(draft.reps) ?? 0) + delta))
    }

    private func bumpRest(_ delta: Int) {
        let next: Int
        if case .seconds(let current) = RestInput.parse(draft.rest) {
            next = max(0, current + delta)
        } else {
            next = model.ledger.restTarget(exercise: draft.row.exercise, routine: model.routine)
        }
        draft.rest = Fmt.duration(Double(next))
    }
}
