import SwiftUI

/// One set line: semantic badge, load × reps, type and comparison note. The whole row is the tap target.
struct SetRowView: View {
    let set: WorkoutSet
    var isSelected = false
    var readOnly = false
    /// Tapping the row selects it: a pending set to fill in, a logged one to edit.
    var onSelect: () -> Void = {}

    var body: some View {
        if readOnly {
            content
        } else {
            Button(action: onSelect) { content }
                .buttonStyle(.plain)
                .accessibilityHint(set.isRegistered ? "Abre a série para editar" : "Seleciona a série para registrar")
        }
    }

    private var repsText: String {
        if !set.isRegistered, let reps = set.preset?.reps, !reps.isEmpty { return reps }
        return set.targetReps.map(String.init) ?? "—"
    }

    private var content: some View {
        HStack(spacing: 14) {
            SetBadge(label: set.orderLabel, type: set.type, filled: set.isRegistered)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let weight = set.weight {
                        Text("\(Fmt.n(weight)) \(set.unit.rawValue)")
                            .font(AppFont.number(17))
                            .foregroundStyle(Color.textPrimary)
                    } else if let preset = set.preset, let load = Parse.number(preset.load) {
                        Text("\(Fmt.n(load)) \(preset.unit.rawValue)")
                            .font(AppFont.number(17, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("— \(set.unit.rawValue)")
                            .font(AppFont.number(17, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                    Text("× \(repsText)")
                        .font(AppFont.number(15, weight: .medium))
                        .foregroundStyle(set.isRegistered ? Color.textPrimary.opacity(0.85) : Color.textSecondary)
                    if let delta = set.delta {
                        DeltaBadge(delta: delta)
                    }
                }
                .monospacedDigit()

                if set.preset != nil {
                    Text("PRÉ-DEFINIDA · toque para registrar")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.linearBlue)
                        .lineLimit(1)
                } else {
                    Text("\(set.type.rawValue) · \(set.note)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(set.type.tintColor.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if set.isRegistered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.statusSuccess)
                    .accessibilityLabel("Concluída")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .background(isSelected ? Color.linearBlueContainer : (set.isRegistered ? Color.appSurfaceHigh : Color.clear),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(isSelected ? Color.linearBlue.opacity(0.5) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
