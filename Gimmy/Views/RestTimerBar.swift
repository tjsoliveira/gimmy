import SwiftUI

/// Rest clock that appears after a set is logged; sits above the tab bar on both tabs.
struct RestTimerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let rest = model.rest {
            TimelineView(.periodic(from: rest.start, by: 0.5)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(rest.start))
                let target = Double(rest.target)
                let due = elapsed >= target
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(due ? "Descanso cumprido" : "Descanso")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(due ? Color.statusSuccess : Color.textMuted)
                            Text(Fmt.duration(elapsed))
                                .font(AppFont.number(30))
                                .foregroundStyle(Color.textPrimary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("alvo \(Fmt.duration(target)) · \(rest.exercise)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)

                        Spacer(minLength: 4)

                        Button {
                            Task { await model.recordRest() }
                        } label: {
                            Text("Começar série")
                                .font(AppFont.bodyBold)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, Spacing.md)
                                .frame(height: 44)
                                .background(due ? Color.statusSuccess : Color.linearBlue,
                                            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busy != nil)

                        Button {
                            model.dismissRest()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(Color.textMuted)
                        .accessibilityLabel("Descartar este descanso sem registrar")
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appSurfaceHigh)
                            Capsule()
                                .fill(due ? Color.statusSuccess : Color.linearBlue)
                                .frame(width: proxy.size.width * min(1, elapsed / max(1, target)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.appSurface)
                .overlay(alignment: .top) { Rectangle().fill(Color.appBorder).frame(height: 1) }
            }
        }
    }
}
