import Foundation
import SwiftUI

/// Set type as shown in the UI. `sheetValue` is what the Registro tab stores in column D.
enum SetType: String, CaseIterable, Identifiable {
    case warmup = "AQUECIMENTO"
    case normal = "NORMAL"
    case dropset = "DROP"
    case restPause = "REST-PAUSE"
    case failure = "FALHA"

    var id: String { rawValue }

    init(kind: String) {
        switch kind {
        case SetKind.warmup: self = .warmup
        case SetKind.drop: self = .dropset
        case SetKind.restPause: self = .restPause
        case SetKind.failure: self = .failure
        default: self = .normal
        }
    }

    var sheetValue: String {
        switch self {
        case .warmup: return SetKind.warmup
        case .normal: return SetKind.normal
        case .dropset: return SetKind.drop
        case .restPause: return SetKind.restPause
        case .failure: return SetKind.failure
        }
    }

    var title: String {
        switch self {
        case .warmup: return "Aquecimento"
        case .normal: return "Normal"
        case .dropset: return "Drop"
        case .restPause: return "Rest-pause"
        case .failure: return "Falha"
        }
    }

    /// Text color on a solid fill of `tintColor`: dark on the light hues, white on the rest.
    var onTint: Color {
        switch self {
        case .warmup, .restPause: return .textInverse
        case .normal, .dropset, .failure: return .white
        }
    }

    var tintColor: Color {
        switch self {
        case .warmup: return .setWarmup
        case .normal: return .setNormal
        case .dropset: return .setDropset
        case .restPause: return .setRestPause
        case .failure: return .setFailure
        }
    }
}

/// One set line as the workout screen shows it, built from a Registro row.
struct WorkoutSet: Identifiable {
    let row: SetRow
    var orderLabel: String
    var type: SetType
    var targetReps: Int?
    var weight: Double?
    var unit: WeightUnit
    var isRegistered: Bool
    var note: String
    var delta: SetDelta?
    /// Values filled in the editor but not saved yet.
    var preset: SetDraft?

    var id: Int { row.row }

    init(row: SetRow, ledger: Ledger, preset: SetDraft? = nil) {
        self.preset = preset
        let last = ledger.lastSet(for: row)
        self.row = row
        orderLabel = row.serie.isEmpty ? "•" : row.serie
        type = SetType(kind: row.kind)
        targetReps = row.reps
        weight = row.isDone ? row.load : nil
        unit = ledger.unit(of: row.exercise)
        isRegistered = row.isDone
        delta = row.isDone ? ledger.delta(row, last) : nil

        var parts: [String] = []
        if let last {
            parts.append("última \(Fmt.set(last.load, last.reps))")
        } else if let day = row.day, ledger.previousDay(exercise: row.exercise, before: day) != nil {
            parts.append("sem essa série na última vez")
        } else {
            parts.append("1ª vez")
        }
        if let rest = row.rest {
            parts.append("desc. \(Fmt.duration(Double(rest)))")
        } else if let pending = row.pendingRest {
            parts.append("desc. \(Fmt.duration(Double(pending))) não gravado")
        }
        note = parts.joined(separator: " · ")
    }
}
