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
                                .foregroundStyle(due ? Color.green : Color.secondary)
                            Text(Fmt.duration(elapsed))
                                .font(.condensed(.largeTitle, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("alvo \(Fmt.duration(target)) · \(rest.exercise)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)

                        Spacer(minLength: 4)

                        Button {
                            Task { await model.recordRest() }
                        } label: {
                            Text("Começar série")
                                .font(.condensed(.headline, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(due ? Color.green : Color.accentColor)
                        .disabled(model.busy != nil)

                        Button {
                            model.dismissRest()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Descartar este descanso sem registrar")
                    }
                    ProgressView(value: min(1, elapsed / max(1, target)))
                        .tint(due ? Color.green : Color.accentColor)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}
