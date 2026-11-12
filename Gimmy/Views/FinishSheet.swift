import SwiftUI

struct FinishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let session = model.currentSession {
                    form(session, model.ledger.stats(session))
                } else {
                    ContentUnavailableView("Nada para finalizar", systemImage: "checkmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Continuar treinando") { dismiss() }
                        .disabled(model.busy != nil)
                }
            }
            .dismissKeyboardToolbar()
        }
        .interactiveDismissDisabled(model.busy != nil)
        .onAppear {
            if minutes.isEmpty, let suggested = model.suggestedDuration() { minutes = String(suggested) }
        }
    }

    private func form(_ session: Session, _ stats: SessionStats) -> some View {
        Form {
            Section {
                LabeledContent("Séries", value: "\(stats.doneSeries) de \(stats.totalSeries)")
                VolumeRow(stats: stats)
                LabeledContent("Descanso médio", value: stats.averageRest.map(Fmt.duration) ?? "—")
                LabeledContent("Recordes", value: "\(stats.records)")
            } header: {
                Text("Finalizar \(session.routine) · \(Fmt.shortDay(session.day))")
            }
            .monospacedDigit()

            Section {
                BigStepper(
                    text: $minutes,
                    keyboard: .numberPad,
                    placeholder: "min",
                    decrementLabel: "Menos 5 minutos",
                    incrementLabel: "Mais 5 minutos",
                    fieldLabel: "Duração em minutos",
                    onDecrement: { bump(-5) },
                    onIncrement: { bump(5) }
                )
            } header: {
                Text("Duração (min)")
            } footer: {
                if stats.pending > 0 {
                    Text(stats.pending == 1 ? "1 série sem carga fica de fora do treino." : "\(stats.pending) séries sem carga ficam de fora do treino.")
                }
            }

            Section {
                ForEach(stats.exercises) { item in
                    HStack(spacing: 8) {
                        Text(item.group.exercise)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let status = item.status {
                            StatusBadge(text: status.text, color: status.color)
                        }
                        if item.record {
                            StatusBadge(text: "Recorde", color: .setWarmup)
                        }
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.statusDanger)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .appListStyle()
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: "Finalizar treino", busy: model.busy) {
                Task { error = await model.finish(minutes: minutes) }
            }
        }
        .onChange(of: minutes) { error = nil }
    }

    private func bump(_ delta: Int) {
        guard let current = Int(minutes) else { minutes = "45"; return }
        minutes = String(max(5, current + delta))
    }
}

/// Volume with the change against the previous session of the same routine.
struct VolumeRow: View {
    let stats: SessionStats

    var body: some View {
        LabeledContent("Volume") {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.n0(stats.volume)) kg")
                if let change = stats.volumeChange, let previous = stats.previousDay {
                    Text("\(Fmt.percent(change)) vs \(Fmt.shortDay(previous))")
                        .font(.caption)
                        .foregroundStyle(change >= 0 ? Color.statusSuccess : Color.statusDanger)
                }
            }
            .monospacedDigit()
        }
    }
}
