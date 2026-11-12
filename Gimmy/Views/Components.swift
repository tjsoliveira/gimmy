import SwiftUI

extension Font {
    /// Kept for the screens that still use text styles; follows the DESIGN.md sans (no condensed width).
    static func condensed(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style).weight(weight)
    }
}

/// Circular set badge: 34 pt, 1.5 pt ring in the set type's color. Tinted fill once logged.
struct SetBadge: View {
    let label: String
    let type: SetType
    let filled: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? type.tintColor.opacity(0.22) : Color.appSurfaceHigh)
            Circle()
                .stroke(type.tintColor, lineWidth: 1.5)
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(type.tintColor)
                .padding(3)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// Pill tag for statuses (Subiu, Caiu, Recorde, 1ª vez).
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppFont.captionBold)
            .tracking(0.5)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

extension ExerciseStatus {
    var color: Color {
        switch kind {
        case .first: return .linearBlue
        case .up: return .statusSuccess
        case .down: return .statusDanger
        case .flat: return .textMuted
        }
    }
}

/// Change in estimated 1RM against the same set last time.
struct DeltaBadge: View {
    let delta: SetDelta

    var body: some View {
        let color: Color = delta.isUp ? .statusSuccess : delta.isDown ? .statusDanger : .textMuted
        HStack(spacing: 2) {
            Image(systemName: delta.isUp ? "arrow.up" : delta.isDown ? "arrow.down" : "equal")
                .font(.system(size: 9, weight: .bold))
            if delta.value != 0 {
                Text(Fmt.n1(abs(delta.value)))
            }
        }
        .font(AppFont.number(12))
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityLabel(delta.isUp ? "Subiu \(Fmt.n1(delta.value))" : delta.isDown ? "Caiu \(Fmt.n1(-delta.value))" : "Igual à última")
    }
}

/// Status and record chips for an exercise.
struct ExerciseChips: View {
    let status: ExerciseStatus?
    let record: Bool

    var body: some View {
        if status != nil || record {
            HStack(spacing: 6) {
                if let status { StatusBadge(text: status.text, color: status.color) }
                if record { StatusBadge(text: "Recorde", color: .setWarmup) }
            }
        }
    }
}

/// − value + control for the finish sheet's duration.
struct BigStepper: View {
    @Binding var text: String
    var keyboard: UIKeyboardType
    var placeholder: String = ""
    var decrementLabel: String
    var incrementLabel: String
    var fieldLabel: String
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDecrement) { Image(systemName: "minus") }
                .buttonStyle(StepperButtonStyle())
                .accessibilityLabel(decrementLabel)

            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(AppFont.number(28))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(fieldLabel)

            Button(action: onIncrement) { Image(systemName: "plus") }
                .buttonStyle(StepperButtonStyle())
                .accessibilityLabel(incrementLabel)
        }
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
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(busy != nil)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color.appBackground)
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

    /// Dark list look for the grouped screens (history, sheets).
    func appListStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
    }
}
