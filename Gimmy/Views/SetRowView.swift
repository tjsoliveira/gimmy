import SwiftUI

/// One set line: semantic badge, load × reps, type and comparison note, compact action button.
struct SetRowView: View {
    let set: WorkoutSet
    var isSelected = false
    var readOnly = false
    var onRegister: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            SetBadge(label: set.orderLabel, type: set.type, filled: set.isRegistered)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let weight = set.weight {
                        Text("\(Fmt.n(weight)) \(set.unit.rawValue)")
                            .font(AppFont.number(17))
                            .foregroundStyle(Color.textPrimary)
                    } else {
                        Text("— \(set.unit.rawValue)")
                            .font(AppFont.number(17, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                    Text("× \(set.targetReps.map(String.init) ?? "—")")
                        .font(AppFont.number(15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    if let delta = set.delta {
                        DeltaBadge(delta: delta)
                    }
                }
                .monospacedDigit()

                Text("\(set.type.rawValue) · \(set.note)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(set.type.tintColor.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if !readOnly {
                Button(action: onRegister) {
                    Text(set.isRegistered ? "Editar" : "Registrar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.linearBlue : Color.appSurfaceHigh,
                                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(isSelected ? Color.clear : Color.appBorder, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isRegistered ? "Editar série \(set.orderLabel)" : "Registrar série \(set.orderLabel)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.linearBlueContainer : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
