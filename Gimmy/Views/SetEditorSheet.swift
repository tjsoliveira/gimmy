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
                let draft = Binding(get: { model.entry ?? current }, set: { model.entry = $0 })
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
                        .keyboardType(.numbersAndPunctuation)
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

    private func bumpRest(_ draft: Binding<SetDraft>, _ delta: Int) {
        let next: Int
        if case .seconds(let current) = RestInput.parse(draft.wrappedValue.rest) {
            next = max(0, current + delta)
        } else {
            next = model.ledger.restTarget(exercise: draft.wrappedValue.row.exercise, routine: model.routine)
        }
        draft.wrappedValue.rest = Fmt.duration(Double(next))
    }
}
