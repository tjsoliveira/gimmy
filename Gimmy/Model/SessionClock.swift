import Foundation

/// The workout's total-time clock: what is stored per workout and what the screen shows.
enum SessionClock {
    enum State: Equatable {
        /// No workout today, or it is already finished.
        case hidden
        /// A workout is open today but its clock never started.
        case notStarted
        /// Counting: `counted` seconds from earlier runs plus the time since `since`.
        case running(since: Date, counted: TimeInterval)
        /// Paused by the user; the time stays at `elapsed`.
        case paused(elapsed: TimeInterval)
    }

    /// Stored per workout: when the current run began (nil while paused) and the time counted before it.
    struct Record: Codable, Equatable {
        var since: Date?
        var counted: TimeInterval = 0

        var isPaused: Bool { since == nil }

        func elapsed(now: Date) -> TimeInterval {
            counted + (since.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }

        func paused(now: Date) -> Record {
            isPaused ? self : Record(since: nil, counted: elapsed(now: now))
        }

        func resumed(now: Date) -> Record {
            isPaused ? Record(since: now, counted: counted) : self
        }

        /// A set was just logged: the clock starts a minute back if it never ran, and resumes if it was paused.
        static func afterSetLogged(_ record: Record?, now: Date) -> Record {
            guard let record else { return Record(since: now.addingTimeInterval(-60)) }
            return record.resumed(now: now)
        }
    }

    /// Past this, a stored clock is stale (forgotten workout) and the screen offers to start again.
    static let maxRunning: TimeInterval = 6 * 3600

    static func state(record: Record?, hasSession: Bool, finished: Bool, isToday: Bool, now: Date) -> State {
        guard hasSession, isToday, !finished else { return .hidden }
        guard let record, record.elapsed(now: now) < maxRunning else { return .notStarted }
        guard let since = record.since else { return .paused(elapsed: record.counted) }
        guard since <= now.addingTimeInterval(60) else { return .notStarted }
        return .running(since: since, counted: record.counted)
    }

    static func elapsed(since start: Date, counted: TimeInterval = 0, now: Date) -> TimeInterval {
        counted + max(0, now.timeIntervalSince(start))
    }
}
