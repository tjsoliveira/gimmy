import SwiftUI

struct AddExerciseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choice = ""
    @State private var custom = ""
    @State private var unit: WeightUnit = .kg
    @State private var sets = 3
    @State private var reps = 12
    @State private var error: String?

    private static let newExercise = "__novo"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Exercício", selection: $choice) {
                        Text("Escolha…").tag("")
                        ForEach(model.ledger.exercises, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        Text("Outro (novo)…").tag(Self.newExercise)
                    }
                    .pickerStyle(.navigationLink)
                    if choice == Self.newExercise {
                        TextField("Nome do exercício novo", text: $custom)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section("Unidade") {
                    Picker("Unidade", selection: $unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper(value: $sets, in: 1...12) {
                        LabeledContent("Séries", value: "\(sets)")
                    }
                    Stepper(value: $reps, in: 1...100) {
                        LabeledContent("Reps", value: "\(reps)")
                    }
                }
                .monospacedDigit()

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.statusDanger)
                    }
                }
            }
            .appListStyle()
            .navigationTitle("Adicionar exercício")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(model.busy != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "Adicionar ao treino", busy: model.busy) {
                    let name = choice == Self.newExercise ? custom : choice
                    Task { error = await model.addExercise(name: name, sets: sets, reps: reps, unit: unit) }
                }
            }
        }
        .interactiveDismissDisabled(model.busy != nil)
        .onChange(of: choice) { _, name in
            error = nil
            if !name.isEmpty && name != Self.newExercise { unit = model.ledger.unit(of: name) }
        }
    }
}
