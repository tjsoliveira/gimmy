import SwiftUI

/// Opens when a set is tapped: the quick-entry card for load and reps, then the set's other options.
/// Nothing is written until Salvar (or Limpar / Remover).
struct SetEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    /// The drop or rest-pause part the card's steppers edit; nil for the set itself.
    @State private var part: UUID?

    var body: some View {
        NavigationStack {
            if let current = model.entry {
                // Writes only while the editor is open: a late write from a closing field must not reopen a saved set.
                let draft = Binding(get: { model.entry ?? current }, set: { if model.entry != nil { model.entry = $0 } })
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            QuickEntryCardView(draft: draft, part: $part, onAddPart: { addMini(draft, select: true) }, onSave: save)
                                .id("entry")
                            options(draft) { id in
                                part = id
                                withAnimation(.smooth) { proxy.scrollTo("entry", anchor: .top) }
                            }
                        }
                        .padding(Spacing.md)
                    }
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

    /// `select` opens a drop or rest-pause part in the card above.
    @ViewBuilder
    private func options(_ draft: Binding<SetDraft>, select: @escaping (UUID) -> Void) -> some View {
        let row = draft.wrappedValue.row

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tipo").captionLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                ForEach(SetType.allCases) { type in
                    let on = SetType(kind: draft.wrappedValue.kind) == type
                    Button {
                        draft.wrappedValue.kind = type.sheetValue
                        if SetKind.chains(type.sheetValue), !model.ledger.hasContinuation(row) {
                            draft.wrappedValue.pause = model.chainPause(kind: type.sheetValue, for: row)
                            if draft.wrappedValue.minis.isEmpty { addMini(draft) }
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

            if SetKind.chains(draft.wrappedValue.kind) {
                chainParts(draft, select: select)
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

    /// Drop or rest-pause parts after this set, logged in the same save. Each is edited in the card above;
    /// here they are listed to pick or remove, with the pause between them.
    @ViewBuilder
    private func chainParts(_ draft: Binding<SetDraft>, select: @escaping (UUID) -> Void) -> some View {
        let row = draft.wrappedValue.row
        let unit = draft.wrappedValue.unit.rawValue
        let drop = draft.wrappedValue.kind == SetKind.drop
        let tint = SetType(kind: draft.wrappedValue.kind).tintColor
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(drop ? "Drops" : "Mini-séries do rest-pause").captionLabel()
                .padding(.top, Spacing.xs)
            if model.ledger.hasContinuation(row) {
                Text(drop
                     ? "Os drops desta série já estão na lista do exercício. Toque neles para editar."
                     : "As mini-séries deste rest-pause já estão na lista do exercício. Toque nelas para editar.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(draft.wrappedValue.minis.enumerated()), id: \.element.id) { index, mini in
                    let selected = part == mini.id
                    let name = drop ? "Drop \(index + 1)" : "Mini-série \(index + 1)"
                    HStack(spacing: Spacing.xs) {
                        Button {
                            select(mini.id)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text(ChainParts.label(serie: row.serie, part: index))
                                    .font(AppFont.number(13))
                                    .foregroundStyle(tint)
                                    .frame(width: 34, alignment: .leading)
                                Text("\(mini.load.isEmpty ? "—" : mini.load) \(unit) × \(mini.reps.isEmpty ? "—" : mini.reps)")
                                    .font(AppFont.number(17, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.textPrimary)
                                Spacer(minLength: Spacing.xs)
                                Text(selected ? "Editando" : "Editar")
                                    .font(AppFont.caption)
                                    .foregroundStyle(selected ? Color.textSecondary : Color.linearBlue)
                            }
                            .padding(.horizontal, Spacing.xs)
                            .frame(minHeight: 44)
                            .background(selected ? Color.linearBlueContainer : Color.appSurfaceLow,
                                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(name): \(mini.load) \(unit), \(mini.reps) reps")
                        .accessibilityHint("Abre nos controles de carga e reps do topo")

                        Button {
                            if part == mini.id { part = nil }
                            draft.wrappedValue.minis.removeAll { $0.id == mini.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 36, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tirar \(drop ? "o drop" : "a mini-série") \(index + 1)")
                    }
                }
                Button {
                    addMini(draft, select: true)
                    select(draft.wrappedValue.minis.last?.id ?? UUID())
                } label: {
                    Label(drop ? "Adicionar drop" : "Adicionar mini-série", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle(height: 40))
                HStack(spacing: Spacing.xs) {
                    Text(drop ? "Pausa entre os drops" : "Pausa entre elas")
                        .font(AppFont.body)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: Spacing.xs)
                    Button { bumpPause(draft, -5) } label: { Image(systemName: "minus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Menos 5 segundos de pausa")
                    TextField(Fmt.duration(Double(ChainParts.defaultPause(draft.wrappedValue.kind))), text: draft.pause)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(AppFont.number(20))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 64, height: 44)
                        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .accessibilityLabel(drop ? "Pausa entre os drops" : "Pausa entre as mini-séries")
                    Button { bumpPause(draft, 5) } label: { Image(systemName: "plus") }
                        .buttonStyle(StepperButtonStyle())
                        .accessibilityLabel("Mais 5 segundos de pausa")
                }
                .padding(.top, Spacing.xxs)
                Text(drop
                     ? "Toque num drop para editar carga e reps no topo. Salvar grava a série e os drops de uma vez, com essa pausa depois de cada um; depois do último, o descanso é o do relógio."
                     : "Toque numa mini-série para editar carga e reps no topo. Salvar grava a série e as mini-séries de uma vez, com essa pausa depois de cada uma; depois da última, o descanso é o do relógio.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    /// A new part: a drop takes about 20 % off the load, a rest-pause part repeats it (see `ChainParts.nextPart`).
    private func addMini(_ draft: Binding<SetDraft>, select: Bool = false) {
        let d = draft.wrappedValue
        let next = ChainParts.nextPart(
            kind: d.kind,
            load: Parse.number(d.minis.last?.load ?? d.load),
            reps: Int(d.minis.last?.reps ?? d.reps) ?? 10,
            first: d.minis.isEmpty,
            unit: d.unit
        )
        if d.pause.isEmpty { draft.wrappedValue.pause = model.chainPause(kind: d.kind, for: d.row) }
        let mini = MiniSet(load: Fmt.loadInput(next.load), reps: String(next.reps))
        draft.wrappedValue.minis.append(mini)
        if select { part = mini.id }
    }

    private func bumpPause(_ draft: Binding<SetDraft>, _ delta: Int) {
        let current: Int
        if case .seconds(let s) = RestInput.parse(draft.wrappedValue.pause) {
            current = s
        } else {
            current = ChainParts.defaultPause(draft.wrappedValue.kind)
        }
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
