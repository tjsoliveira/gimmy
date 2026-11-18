import SwiftUI

/// Card that logs a set: full-width load and reps steppers, quick chips, kg/lb toggle, save.
/// For a drop or rest-pause, a row on top picks what the steppers edit: the set itself or one of its parts.
struct QuickEntryCardView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: SetDraft
    /// The drop or rest-pause part the steppers edit; nil for the set itself.
    @Binding var part: UUID?
    var onAddPart: () -> Void = {}
    var onSave: () -> Void

    /// Parts can be typed here when the set chains and its parts aren't rows of the sheet yet.
    private var partsEditable: Bool { SetKind.chains(draft.kind) && !model.ledger.hasContinuation(draft.row) }

    private var partIndex: Int? {
        guard partsEditable, let part else { return nil }
        return draft.minis.firstIndex { $0.id == part }
    }

    private var loadText: Binding<String> {
        Binding(
            get: { partIndex.map { draft.minis[$0].load } ?? draft.load },
            set: { value in if let i = partIndex { draft.minis[i].load = value } else { draft.load = value } }
        )
    }

    private var repsText: Binding<String> {
        Binding(
            get: { partIndex.map { draft.minis[$0].reps } ?? draft.reps },
            set: { value in if let i = partIndex { draft.minis[i].reps = value } else { draft.reps = value } }
        )
    }

    private var step: Double {
        partIndex.map { draft.unit.defaultStep(for: Parse.number(draft.minis[$0].load)) } ?? draft.step
    }

    var body: some View {
        let unit = draft.unit.rawValue
        let step = self.step
        VStack(spacing: Spacing.sm) {
            header

            if partsEditable {
                partPicker
            }

            VStack(spacing: Spacing.sm) {
                StepperBlock(
                    title: "Carga (\(unit))",
                    text: loadText,
                    keyboard: .decimalPad,
                    decrementLabel: "Menos \(Fmt.n(step)) \(unit)",
                    incrementLabel: "Mais \(Fmt.n(step)) \(unit)",
                    onDecrement: { bumpLoad(-step) },
                    onIncrement: { bumpLoad(step) }
                ) {
                    ForEach(draft.unit.cardAdds, id: \.self) { amount in
                        QuickIncrementChip(title: "+\(Fmt.n(amount))") { bumpLoad(amount) }
                            .accessibilityLabel("Somar \(Fmt.n(amount)) \(unit)")
                    }
                }

                StepperBlock(
                    title: "Repetições",
                    text: repsText,
                    keyboard: .numberPad,
                    decrementLabel: "Menos uma rep",
                    incrementLabel: "Mais uma rep",
                    onDecrement: { bumpReps(-1) },
                    onIncrement: { bumpReps(1) }
                ) {
                    ForEach(ChainParts.repsChips(kind: draft.kind, editingPart: partIndex != nil), id: \.self) { reps in
                        QuickIncrementChip(title: "\(reps)") { repsText.wrappedValue = String(reps) }
                            .accessibilityLabel("\(reps) reps")
                    }
                }
            }

            footnote

            Button(action: onSave) {
                HStack(spacing: 8) {
                    if model.busy != nil {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    }
                    Text(model.busy ?? (draft.row.isDone ? "Salvar alterações" : "Salvar série"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.busy != nil)
        }
        .appCard()
        .onChange(of: draft.unit) { _, unit in
            draft.step = unit.defaultStep(for: Parse.number(draft.load))
        }
        .onChange(of: draft.load) { model.entryError = nil }
        .onChange(of: draft.reps) { model.entryError = nil }
        .onChange(of: draft.minis) { model.entryError = nil }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.statusSuccess)
                        .frame(width: 6, height: 6)
                    Text("Série \(ChainParts.label(serie: draft.row.serie, part: partIndex)) · \(SetType(kind: draft.kind).title)")
                        .captionLabel(.textSecondary)
                        .lineLimit(1)
                }
                Text(draft.row.exercise)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            UnitToggle(selection: $draft.unit)
        }
    }

    /// The set and each of its parts; the chosen one is what the steppers edit.
    private var partPicker: some View {
        let drop = draft.kind == SetKind.drop
        let tint = SetType(kind: draft.kind).tintColor
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                PartChip(label: ChainParts.label(serie: draft.row.serie, part: nil),
                         detail: ChainParts.summary(load: draft.load, reps: draft.reps),
                         tint: .textPrimary, selected: partIndex == nil) { part = nil }
                    .accessibilityLabel("Série principal")
                ForEach(Array(draft.minis.enumerated()), id: \.element.id) { index, mini in
                    PartChip(label: ChainParts.label(serie: draft.row.serie, part: index),
                             detail: ChainParts.summary(load: mini.load, reps: mini.reps),
                             tint: tint, selected: partIndex == index) { part = mini.id }
                        .accessibilityLabel(drop ? "Drop \(index + 1)" : "Mini-série \(index + 1)")
                }
                Button(action: onAddPart) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 46)
                        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.appBorderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(drop ? "Adicionar drop" : "Adicionar mini-série")
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        let reps = Int(repsText.wrappedValue) ?? 0
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.entryError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.statusDanger)
            } else if draft.unit != model.ledger.unit(of: draft.row.exercise) {
                Text("A unidade vale para todo o histórico de \(draft.row.exercise). Grava ao salvar a série.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            } else if let estimate = OneRM.estimate(Parse.number(loadText.wrappedValue), reps) {
                // The comparison with last time is for the set itself; parts only show their estimate.
                let previous = partIndex == nil ? draft.last.flatMap { OneRM.estimate($0.load, $0.reps) } : nil
                let change = previous.map { ((estimate - $0) * 10).rounded() / 10 }
                HStack(spacing: 6) {
                    Text("1RM est. \(Fmt.n1(estimate)) \(draft.unit.rawValue)")
                        .foregroundStyle(Color.textSecondary)
                    if let change, change != 0 {
                        Label("\(Fmt.n1(abs(change))) vs. a última", systemImage: change > 0 ? "arrow.up" : "arrow.down")
                            .foregroundStyle(change > 0 ? Color.statusSuccess : Color.statusDanger)
                    } else if change != nil {
                        Text("· igual à última").foregroundStyle(Color.textSecondary)
                    }
                }
                .font(AppFont.number(12, weight: .semibold))
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bumpLoad(_ delta: Double) {
        let value = max(0, (((Parse.number(loadText.wrappedValue) ?? 0) + delta) * 100).rounded() / 100)
        loadText.wrappedValue = Fmt.loadInput(value)
    }

    private func bumpReps(_ delta: Int) {
        repsText.wrappedValue = String(max(1, (Int(repsText.wrappedValue) ?? 0) + delta))
    }
}

/// One entry of the part picker: "3.1" over "47,5×8".
private struct PartChip: View {
    let label: String
    let detail: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(AppFont.number(13))
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 64, minHeight: 46)
            .background(selected ? Color.linearBlueContainer : Color.appSurfaceLow,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(selected ? Color.linearBlue.opacity(0.6) : Color.appBorderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(detail)
    }
}

/// Title, a large − value + row, and a row of quick chips. Full card width.
private struct StepperBlock<Chips: View>: View {
    let title: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let decrementLabel: String
    let incrementLabel: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    @ViewBuilder let chips: () -> Chips

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .captionLabel()

            HStack(spacing: Spacing.xs) {
                Button(action: onDecrement) { Image(systemName: "minus") }
                    .buttonStyle(LargeStepperStyle())
                    .accessibilityLabel(decrementLabel)

                TextField("—", text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(AppFont.number(40))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel(title)

                Button(action: onIncrement) { Image(systemName: "plus") }
                    .buttonStyle(LargeStepperStyle())
                    .accessibilityLabel(incrementLabel)
            }

            HStack(spacing: 6) { chips() }
        }
        .padding(Spacing.sm)
        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// 56 pt stepper key for the editor.
private struct LargeStepperStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 56, height: 56)
            .background(configuration.isPressed ? Color.appSurfaceHighest : Color.appSurfaceHigh,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct QuickIncrementChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// KG / LBS segmented toggle from the card header.
struct UnitToggle: View {
    @Binding var selection: WeightUnit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WeightUnit.allCases, id: \.self) { unit in
                let on = unit == selection
                Button {
                    selection = unit
                } label: {
                    Text(unit == .kg ? "KG" : "LBS")
                        .font(.system(size: 11, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? Color.textPrimary : Color.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(on ? Color.appSurfaceHigh : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unidade")
    }
}
