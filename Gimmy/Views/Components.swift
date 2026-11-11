import SwiftUI

extension Font {
    /// The app's one typographic signature: condensed SF for names and numbers, echoing the old Barlow Condensed.
    static func condensed(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style).weight(weight).width(.condensed)
    }
}

enum SetColors {
    static func color(for kind: String) -> Color? {
        switch kind {
        case SetKind.warmup: return .orange
        case SetKind.drop: return .purple
        case SetKind.failure: return .red
        default: return nil
        }
    }
}

/// Circle with the set number. Filled once the set is logged.
struct SetBadge: View {
    let label: String
    let kind: String
    let done: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        let typeColor = SetColors.color(for: kind)
        let stroke = typeColor ?? (done ? Color.accentColor : Color(.separator))
        ZStack {
            Circle()
                .fill(done ? stroke : Color.clear)
            Circle()
                .strokeBorder(stroke, lineWidth: 2)
            Text(label)
                .font(.condensed(.headline, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(done ? Color.white : (typeColor ?? Color.secondary))
                .padding(4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.condensed(.subheadline, weight: .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

extension ExerciseStatus {
    var color: Color {
        switch kind {
        case .first: return .accentColor
        case .up: return .green
        case .down: return .red
        case .flat: return .secondary
        }
    }
}

struct DeltaBadge: View {
    let delta: SetDelta

    var body: some View {
        let color: Color = delta.isUp ? .green : delta.isDown ? .red : .secondary
        HStack(spacing: 2) {
            Image(systemName: delta.isUp ? "arrow.up" : delta.isDown ? "arrow.down" : "equal")
                .imageScale(.small)
            if delta.value != 0 {
                Text(Fmt.n1(abs(delta.value)))
            }
        }
        .font(.condensed(.headline, weight: .bold))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(delta.isUp ? "Subiu \(Fmt.n1(delta.value))" : delta.isDown ? "Caiu \(Fmt.n1(-delta.value))" : "Igual à última")
    }
}

/// Exercise name plus its status and record chips, used as a list section header.
struct ExerciseHeader: View {
    let name: String
    let status: ExerciseStatus?
    let record: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.condensed(.title3))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                StatusBadge(text: status.text, color: status.color)
            }
            if record {
                StatusBadge(text: "Recorde", color: .orange)
            }
        }
        .textCase(nil)
        .padding(.top, 8)
    }
}

/// Content of one set line: badge, load × reps, comparison with last time.
struct SetRowContent: View {
    @Environment(AppModel.self) private var model
    let row: SetRow

    var body: some View {
        let ledger = model.ledger
        let last = ledger.lastSet(for: row)
        let unit = ledger.unit(of: row.exercise).rawValue
        let delta = row.isDone ? ledger.delta(row, last) : nil

        HStack(spacing: 12) {
            SetBadge(label: row.serie.isEmpty ? "•" : row.serie, kind: row.kind, done: row.isDone)
            VStack(alignment: .leading, spacing: 2) {
                value(unit: unit)
                Text(subtitle(last: last))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let delta {
                DeltaBadge(delta: delta)
            } else if !row.isDone {
                Text("Registrar")
                    .font(.condensed(.headline))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func value(unit: String) -> some View {
        let big = Font.condensed(.title2)
        if row.isDone {
            (Text(Fmt.n(row.load ?? 0)) + Text(" \(unit)").font(.condensed(.body, weight: .medium)).foregroundColor(.secondary) + Text(" × \(row.reps ?? 0)"))
                .font(big)
                .monospacedDigit()
                .foregroundStyle(.primary)
        } else {
            Text("— \(unit) × \(row.reps.map(String.init) ?? "—")")
                .font(big)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(last: SetRow?) -> String {
        var parts: [String] = []
        switch row.kind {
        case SetKind.warmup: parts.append("aquecimento")
        case SetKind.drop: parts.append("drop")
        case SetKind.failure: parts.append("falha")
        default: break
        }
        if let last {
            parts.append("última \(Fmt.set(last.load, last.reps))")
        } else if let day = row.day, model.ledger.previousDay(exercise: row.exercise, before: day) != nil {
            parts.append("sem essa série na última vez")
        } else {
            parts.append("1ª vez")
        }
        if let rest = row.rest {
            parts.append("desc. \(Fmt.duration(Double(rest)))")
        } else if let pending = row.pendingRest {
            parts.append("desc. \(Fmt.duration(Double(pending))) não gravado")
        }
        return parts.joined(separator: " · ")
    }
}

/// Large − value + control for loads, reps and times: thumb-sized for use between sets.
struct BigStepper: View {
    @Binding var text: String
    var keyboard: UIKeyboardType
    var placeholder: String = ""
    var decrementLabel: String
    var incrementLabel: String
    var fieldLabel: String
    var onDecrement: () -> Void
    var onIncrement: () -> Void
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.title2.weight(.semibold))
                    .frame(width: size, height: size)
            }
            .accessibilityLabel(decrementLabel)

            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(.condensed(.largeTitle, weight: .bold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: size)
                .accessibilityLabel(fieldLabel)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: size, height: size)
            }
            .accessibilityLabel(incrementLabel)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .padding(.vertical, 4)
    }
}

/// Full-width primary action pinned above the home indicator.
struct BottomActionButton: View {
    let title: String
    var busy: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy != nil { ProgressView().tint(.white) }
                Text(busy ?? title)
                    .font(.condensed(.title3, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(busy != nil)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

extension View {
    func dismissKeyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
