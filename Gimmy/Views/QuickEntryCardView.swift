import SwiftUI

/// Inline card that logs the selected set: load and reps steppers, quick chips, kg/lb toggle, save.
struct QuickEntryCardView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: SetDraft
    var onSave: () -> Void

    var body: some View {
        let unit = draft.unit.rawValue
        VStack(spacing: Spacing.sm) {
            header

            HStack(alignment: .top, spacing: Spacing.sm) {
                StepperColumn(
                    title: "Carga (\(unit))",
                    text: $draft.load,
                    keyboard: .decimalPad,
                    decrementLabel: "Menos \(Fmt.n(draft.step)) \(unit)",
                    incrementLabel: "Mais \(Fmt.n(draft.step)) \(unit)",
                    onDecrement: { bumpLoad(-draft.step) },
                    onIncrement: { bumpLoad(draft.step) }
                ) {
                    ForEach(draft.unit.cardAdds, id: \.self) { amount in
                        QuickIncrementChip(title: "+\(Fmt.n(amount))") { bumpLoad(amount) }
                            .accessibilityLabel("Somar \(Fmt.n(amount)) \(unit)")
                    }
                }

                StepperColumn(
                    title: "Repetições",
                    text: $draft.reps,
                    keyboard: .numberPad,
                    decrementLabel: "Menos uma rep",
                    incrementLabel: "Mais uma rep",
                    onDecrement: { bumpReps(-1) },
                    onIncrement: { bumpReps(1) }
                ) {
                    ForEach([8, 10, 12], id: \.self) { reps in
                        QuickIncrementChip(title: "\(reps)") { draft.reps = String(reps) }
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
                    Text(model.busy ?? "Salvar série")
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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.statusSuccess)
                        .frame(width: 6, height: 6)
                    Text("Série \(draft.row.serie.isEmpty ? "•" : draft.row.serie) · \(SetType(kind: draft.kind).title)")
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

    @ViewBuilder
    private var footnote: some View {
        let reps = Int(draft.reps) ?? 0
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.entryError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.statusDanger)
            } else if draft.unit != model.ledger.unit(of: draft.row.exercise) {
                Text("A unidade vale para todo o histórico de \(draft.row.exercise). Grava ao salvar a série.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            } else if let estimate = OneRM.estimate(Parse.number(draft.load), reps) {
                let previous = draft.last.flatMap { OneRM.estimate($0.load, $0.reps) }
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
        let value = max(0, (((Parse.number(draft.load) ?? 0) + delta) * 100).rounded() / 100)
        draft.load = Fmt.loadInput(value)
    }

    private func bumpReps(_ delta: Int) {
        draft.reps = String(max(1, (Int(draft.reps) ?? 0) + delta))
    }
}

/// Title, − value +, and a row of quick chips.
private struct StepperColumn<Chips: View>: View {
    let title: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let decrementLabel: String
    let incrementLabel: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    @ViewBuilder let chips: () -> Chips

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .captionLabel()

            HStack(spacing: 4) {
                Button(action: onDecrement) { Image(systemName: "minus") }
                    .buttonStyle(CompactStepperStyle())
                    .accessibilityLabel(decrementLabel)

                TextField("—", text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(AppFont.number(26))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .accessibilityLabel(title)

                Button(action: onIncrement) { Image(systemName: "plus") }
                    .buttonStyle(CompactStepperStyle())
                    .accessibilityLabel(incrementLabel)
            }

            HStack(spacing: 6) { chips() }
        }
        .padding(Spacing.sm)
        .background(Color.appSurfaceLow, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// 36 pt stepper key from the design; the hit area stays 44 pt tall.
private struct CompactStepperStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 36)
            .background(configuration.isPressed ? Color.appSurfaceHighest : Color.appSurfaceHigh,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

struct QuickIncrementChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
