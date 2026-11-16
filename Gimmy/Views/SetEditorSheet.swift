import SwiftUI

/// Opens when a set is tapped: the quick-entry card for load and reps, then the set's other options.
/// Nothing is written until Salvar (or Limpar / Remover).
struct SetEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            if let current = model.entry {
                // Writes only while the editor is open: a late write from a closing field must not reopen a saved set.
                let draft = Binding(get: { model.entry ?? current }, set: { if model.entry != nil { model.entry = $0 } })
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        QuickEntryCardView(draft: draft, onSave: save)
                        options(draft)
                    }
                    .padding(Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.appBackground)
                .navigationTitle(current.row.isDone ? "Editar série" : "Registrar série")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.appBackground, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                            .disabled(model.busy != nil)
                    }
                }
                .dismissKeyboardToolbar()
                // The rest clock keeps running while a set is edited.
                .safeAreaInset(edge: .bottom) { RestTimerBar() }
                .confirmationDialog("Remover esta série?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                    Button("Remover série", role: .destructive) {
                        Task { model.entryError = await model.remove(current) }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("A série sai do treino e da planilha, e as seguintes deste exercício são renumeradas. Para só apagar a carga e manter a série no lugar, use Limpar série.")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.busy != nil)
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let draft = model.entry else { return }
        Task { model.entryError = await model.save(draft, clear: false) }
    }

    @ViewBuilder
    private func options(_ draft: Binding<SetDraft>) -> some View {
        let row = draft.wrappedValue.row

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tipo").captionLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                ForEach(SetType.allCases) { type in
                    let on = SetType(kind: draft.wrappedValue.kind) == type
                    Button {
                        draft.wrappedValue.kind = type.sheetValue
                        if type == .restPause, draft.wrappedValue.minis.isEmpty, !model.ledger.hasContinuation(row) {
                            addMini(draft)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(type.tintColor).frame(width: 6, height: 6)
                            Text(type.title)
                                .font(.system(size: 13, weight: on ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(on ? Color.textPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.appSurfaceHighest : Color.appSurfaceHigh,
                                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(on ? type.tintColor.opacity(0.7) : Color.appBorderDefault, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            if draft.wrappedValue.kind == SetKind.restPause {
                restPauseParts(draft)
            }

            if let last = draft.wrappedValue.last {
                Button {
                    draft.wrappedValue.load = Fmt.loadInput(last.load)
                    draft.wrappedValue.reps = String(last.reps ?? 0)
                } label: {
                    Label("Repetir a última: \(Fmt.n(last.load ?? 0)) \(draft.wrappedValue.unit.rawValue) × \(last.reps ?? 0)",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                .padding(.top, Spacing.xxs)
            }

            if row.isDone {
                Text("Descanso depois desta série (min:seg)").captionLabel()
                    .padding(.top, Spacing.xs)
                HStack(spacing: Spacing.xs) {
                    Button { bumpRest(draft, -15) } label: { Image(systemName: "minus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Menos 15 segundos")
                    TextField("sem registro", text: draft.rest)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(AppFont.number(22))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .accessibilityLabel("Descanso")
                    Button { bumpRest(draft, 15) } label: { Image(systemName: "plus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Mais 15 segundos")
                }
                Text("Digite só números: 130 vira 1:30, 45 vira 0:45.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .appCard()

        VStack(spacing: Spacing.xs) {
            if row.isDone {
                Button {
                    Task { model.entryError = await model.save(draft.wrappedValue, clear: true) }
                } label: {
                    Label("Limpar série", systemImage: "eraser")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44, foreground: .statusDanger, background: .appSurfaceLow))
                .disabled(model.busy != nil)
            }
            Button {
                confirmingRemoval = true
            } label: {
                Label("Remover série", systemImage: "trash")
            }
            .buttonStyle(SecondaryButtonStyle(height: 44, foreground: .statusDanger, background: .appSurfaceLow))
            .disabled(model.busy != nil)
        }
    }

    /// Rest-pause parts after this set, logged in the same save.
    @ViewBuilder
    private func restPauseParts(_ draft: Binding<SetDraft>) -> some View {
        let row = draft.wrappedValue.row
        let unit = draft.wrappedValue.unit.rawValue
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Mini-séries do rest-pause").captionLabel()
                .padding(.top, Spacing.xs)
            if model.ledger.hasContinuation(row) {
                Text("As mini-séries deste rest-pause já estão na lista do exercício. Toque nelas para editar.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(draft.wrappedValue.minis.enumerated()), id: \.element.id) { index, mini in
                    HStack(spacing: Spacing.xs) {
                        Text("\(row.serie.isEmpty ? "•" : row.serie).\(index + 1)")
                            .font(AppFont.number(13))
                            .foregroundStyle(Color.setRestPause)
                            .frame(width: 34)
                        MiniField(text: miniBinding(draft, mini.id, \.load), keyboard: .decimalPad, suffix: unit,
                                  label: "Carga da mini-série \(index + 1)")
                        Text("×").foregroundStyle(Color.textMuted)
                        MiniField(text: miniBinding(draft, mini.id, \.reps), keyboard: .numberPad, suffix: "reps",
                                  label: "Reps da mini-série \(index + 1)")
                        Button {
                            draft.wrappedValue.minis.removeAll { $0.id == mini.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 36, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tirar a mini-série \(index + 1)")
                    }
                }
                Button {
                    addMini(draft)
                } label: {
                    Label("Adicionar mini-série", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle(height: 40))
                HStack(spacing: Spacing.xs) {
                    Text("Pausa entre elas")
                        .font(AppFont.body)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: Spacing.xs)
                    Button { bumpPause(draft, -5) } label: { Image(systemName: "minus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Menos 5 segundos de pausa")
                    TextField("0:15", text: draft.pause)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(AppFont.number(20))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 64, height: 44)
                        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .accessibilityLabel("Pausa entre as mini-séries")
                    Button { bumpPause(draft, 5) } label: { Image(systemName: "plus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Mais 5 segundos de pausa")
                }
                .padding(.top, Spacing.xxs)
                Text("Salvar grava a série e as mini-séries de uma vez, com essa pausa depois de cada uma. Depois da última, o descanso é o do relógio.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func addMini(_ draft: Binding<SetDraft>) {
        let d = draft.wrappedValue
        let load = d.minis.last?.load ?? d.load
        let baseReps = Int(d.minis.last?.reps ?? d.reps) ?? 10
        let reps = d.minis.isEmpty ? RestPause.suggestedReps(after: baseReps) : baseReps
        draft.wrappedValue.minis.append(MiniSet(load: load, reps: String(reps)))
    }

    private func miniBinding(_ draft: Binding<SetDraft>, _ id: UUID, _ field: WritableKeyPath<MiniSet, String>) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue.minis.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { value in
                if let i = draft.wrappedValue.minis.firstIndex(where: { $0.id == id }) {
                    draft.wrappedValue.minis[i][keyPath: field] = value
                }
            }
        )
    }

    private func bumpPause(_ draft: Binding<SetDraft>, _ delta: Int) {
        let current: Int
        if case .seconds(let s) = RestInput.parse(draft.wrappedValue.pause) { current = s } else { current = RestPause.defaultPause }
        draft.wrappedValue.pause = Fmt.duration(Double(min(600, max(5, current + delta))))
    }

    private func bumpRest(_ draft: Binding<SetDraft>, _ delta: Int) {
        let next: Int
        if case .seconds(let current) = RestInput.parse(draft.wrappedValue.rest) {
            next = max(0, current + delta)
        } else {
            next = model.ledger.restTarget(exercise: draft.wrappedValue.row.exercise, routine: model.routine, day: model.day)
        }
        draft.wrappedValue.rest = Fmt.duration(Double(next))
    }
}

/// Small numeric field used by the rest-pause parts.
private struct MiniField: View {
    @Binding var text: String
    let keyboard: UIKeyboardType
    let suffix: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            TextField("—", text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(AppFont.number(17))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .accessibilityLabel(label)
            Text(suffix)
                .font(AppFont.caption)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
