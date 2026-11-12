import Foundation

/// When the workout screen shows the total-time clock.
enum SessionClock {
    enum State: Equatable {
        /// No workout today, or it is already finished.
        case hidden
        /// A workout is open today but its start time is unknown.
        case notStarted
        case running(since: Date)
    }

    /// Past this, a stored start time is stale (forgotten workout) and not shown as running.
    static let maxRunning: TimeInterval = 6 * 3600

    static func state(start: Date?, hasSession: Bool, finished: Bool, isToday: Bool, now: Date) -> State {
        guard hasSession, isToday, !finished else { return .hidden }
        guard let start, start <= now.addingTimeInterval(60), now.timeIntervalSince(start) < maxRunning else {
            return .notStarted
        }
        return .running(since: start)
    }

    static func elapsed(since start: Date, now: Date) -> TimeInterval { max(0, now.timeIntervalSince(start)) }
}
