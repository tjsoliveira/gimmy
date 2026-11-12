import Foundation

/// Day keys are "yyyy-MM-dd" strings, so they compare in calendar order.
enum DayKey {
    static func make(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func from(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return make(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// Google Sheets date serial (days since 1899-12-30).
    static func fromSerial(_ serial: Double) -> String {
        let date = Date(timeIntervalSince1970: (serial.rounded() - 25569) * 86400)
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return make(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func serial(_ key: String) -> Int {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return 0 }
        return Int((date.timeIntervalSince1970 / 86400).rounded()) + 25569
    }
}

enum Parse {
    static func number(_ cell: Cell) -> Double? {
        switch cell {
        case .number(let value): return value
        case .text(let value): return number(value)
        default: return nil
        }
    }

    /// Accepts "42,5", "1.234,5" and "42.5".
    static func number(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(s), value.isFinite else { return nil }
        return value
    }

    static func text(_ cell: Cell) -> String {
        switch cell {
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let value): return value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "TRUE" : "FALSE"
        case .empty: return ""
        }
    }

    static func day(_ cell: Cell) -> String? {
        switch cell {
        case .number(let serial):
            return DayKey.fromSerial(serial)
        case .text(let raw):
            let s = raw.trimmingCharacters(in: .whitespaces)
            let slash = s.split(separator: "/")
            if slash.count == 3, slash[2].count == 4,
               let d = Int(slash[0]), let m = Int(slash[1]), let y = Int(slash[2]) {
                return DayKey.make(y, m, d)
            }
            let dash = s.prefix(10).split(separator: "-")
            if dash.count == 3, dash[0].count == 4,
               let y = Int(dash[0]), let m = Int(dash[1]), let d = Int(dash[2]) {
                return DayKey.make(y, m, d)
            }
            if let serial = Double(s) { return DayKey.fromSerial(serial) }
            return nil
        default:
            return nil
        }
    }

    /// Rest column: a time-of-day fraction, or "m:ss" / "h:mm:ss".
    static func seconds(_ cell: Cell) -> Int? {
        switch cell {
        case .number(let fraction):
            return Int((fraction * 86400).rounded())
        case .text(let raw):
            let p = raw.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
            guard (2...3).contains(p.count), p.last?.count == 2 else { return nil }
            let n = p.compactMap { Int($0) }
            guard n.count == p.count else { return nil }
            return n.count == 3 ? n[0] * 3600 + n[1] * 60 + n[2] : n[0] * 60 + n[1]
        default:
            return nil
        }
    }

    /// Workout duration column: a time-of-day fraction, or "h:mm".
    static func minutes(_ cell: Cell) -> Int? {
        switch cell {
        case .number(let fraction):
            return Int((fraction * 1440).rounded())
        case .text(let raw):
            let p = raw.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
            guard (2...3).contains(p.count), p[1].count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
            return h * 60 + m
        default:
            return nil
        }
    }
}

enum Fmt {
    private static func formatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        return f
    }

    private static let upTo2 = formatter(min: 0, max: 2)
    private static let one = formatter(min: 1, max: 1)
    private static let whole = formatter(min: 0, max: 0)

    static func n(_ value: Double) -> String { upTo2.string(from: NSNumber(value: value)) ?? "\(value)" }
    static func n1(_ value: Double) -> String { one.string(from: NSNumber(value: value)) ?? "\(value)" }
    static func n0(_ value: Double) -> String { whole.string(from: NSNumber(value: value)) ?? "\(value)" }

    static func set(_ load: Double?, _ reps: Int?) -> String { "\(n(load ?? 0))×\(reps ?? 0)" }

    /// A load as typed in a field: no thousands separator.
    static func loadInput(_ value: Double?) -> String {
        guard let value else { return "" }
        return n(value).replacingOccurrences(of: ".", with: "")
    }

    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Elapsed workout time: "42:13" under an hour, "1:05:09" above.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h):" + String(format: "%02d:%02d", m, sec) : "\(m):" + String(format: "%02d", sec)
    }

    static func minutes(_ m: Int?) -> String {
        guard let m else { return "—" }
        return m >= 60 ? "\(m / 60)h" + String(format: "%02d", m % 60) : "\(m) min"
    }

    static func percent(_ ratio: Double) -> String {
        let v = (ratio * 1000).rounded() / 10
        return (v > 0 ? "+" : v < 0 ? "−" : "") + n1(abs(v)) + "%"
    }

    static func shortDay(_ key: String) -> String {
        let p = key.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : key
    }

    static func weekday(_ key: String) -> String {
        guard let date = DayKey.date(key) else { return "" }
        let names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        return names[(Calendar.current.component(.weekday, from: date) - 1) % 7]
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f
    }()

    static func month(_ key: String) -> String {
        guard let date = DayKey.date(key) else { return key }
        let text = monthFormatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Rest typed by hand: "1:30", "130" (= 1:30) or "90" (seconds). Empty clears.
enum RestInput: Equatable {
    case empty
    case seconds(Int)
    case invalid

    static func parse(_ raw: String) -> RestInput {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: ",", with: ":")
        if s.isEmpty { return .empty }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard (1...2).contains(parts[0].count), (1...2).contains(parts[1].count),
                  let m = Int(parts[0]), let sec = Int(parts[1]), sec < 60, m >= 0, sec >= 0 else { return .invalid }
            return .seconds(m * 60 + sec)
        }
        guard parts.count == 1, (1...4).contains(s.count),
              s.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(s) else { return .invalid }
        if s.count >= 3 {
            let sec = v % 100
            return sec < 60 ? .seconds((v / 100) * 60 + sec) : .invalid
        }
        return .seconds(v)
    }
}
