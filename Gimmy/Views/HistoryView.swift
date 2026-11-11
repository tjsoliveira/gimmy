import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.historyPath) {
            let sessions = model.ledger.sessions()
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Nenhum treino ainda",
                        systemImage: "calendar",
                        description: Text("Os treinos que você registrar aparecem aqui.")
                    )
                } else {
                    List {
                        ForEach(months(sessions), id: \.title) { month in
                            Section(month.title) {
                                ForEach(month.sessions) { session in
                                    NavigationLink(value: session.key) {
                                        HistoryRow(session: session, stats: model.ledger.stats(session))
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Histórico")
            .refreshable { await model.reload() }
            .navigationDestination(for: String.self) { key in
                SessionDetailView(key: key, allowsEditing: true)
            }
            .safeAreaInset(edge: .bottom) { RestTimerBar() }
        }
    }

    private struct Month {
        var title: String
        var sessions: [Session]
    }

    private func months(_ sessions: [Session]) -> [Month] {
        var out: [Month] = []
        for session in sessions {
            let title = Fmt.month(session.day)
            if out.last?.title == title {
                out[out.count - 1].sessions.append(session)
            } else {
                out.append(Month(title: title, sessions: [session]))
            }
        }
        return out
    }
}

private struct HistoryRow: View {
    let session: Session
    let stats: SessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.routine)
                    .font(.condensed(.title3))
                Spacer()
                Text("\(Fmt.weekday(session.day)), \(Fmt.shortDay(session.day))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            summary
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if stats.upCount + stats.downCount + stats.records > 0 {
                HStack(spacing: 6) {
                    if stats.upCount > 0 {
                        StatusBadge(text: "\(stats.upCount) \(stats.upCount == 1 ? "subiu" : "subiram")", color: .green)
                    }
                    if stats.downCount > 0 {
                        StatusBadge(text: "\(stats.downCount) \(stats.downCount == 1 ? "caiu" : "caíram")", color: .red)
                    }
                    if stats.records > 0 {
                        StatusBadge(text: "\(stats.records) \(stats.records == 1 ? "recorde" : "recordes")", color: .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: Text {
        var text = Text("\(stats.doneSeries) \(stats.doneSeries == 1 ? "série" : "séries") · \(Fmt.n0(stats.volume)) kg")
        if let change = stats.volumeChange {
            text = text + Text(" \(Fmt.percent(change))")
                .fontWeight(.semibold)
                .foregroundColor(change >= 0 ? .green : .red)
        }
        if let duration = stats.duration { text = text + Text(" · \(Fmt.minutes(duration))") }
        if let rest = stats.averageRest { text = text + Text(" · desc. \(Fmt.duration(rest))") }
        return text
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let key: String
    let allowsEditing: Bool

    var body: some View {
        Group {
            if let session = model.ledger.session(key) {
                let stats = model.ledger.stats(session)
                List {
                    Section {
                        LabeledContent("Duração", value: Fmt.minutes(stats.duration))
                        VolumeRow(stats: stats)
                        LabeledContent("Séries", value: "\(stats.doneSeries)")
                        LabeledContent("Descanso médio", value: stats.averageRest.map(Fmt.duration) ?? "—")
                    } header: {
                        Text("\(Fmt.weekday(session.day)), \(Fmt.shortDay(session.day))")
                    }
                    .monospacedDigit()

                    ForEach(stats.exercises) { item in
                        Section {
                            ForEach(item.group.rows.filter(\.isDone)) { row in
                                SetRowContent(row: row)
                            }
                        } header: {
                            ExerciseHeader(name: item.group.exercise, status: item.status, record: item.record)
                        }
                    }

                    if allowsEditing {
                        Section {
                            Button("Abrir este treino para editar", systemImage: "pencil") {
                                model.openForEditing(session)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(session.routine)
            } else {
                ContentUnavailableView("Treino não encontrado", systemImage: "questionmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
