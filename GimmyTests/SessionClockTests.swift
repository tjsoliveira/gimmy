@testable import Gimmy
import XCTest

final class SessionClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private typealias Record = SessionClock.Record

    private func state(_ record: Record?, hasSession: Bool = true, finished: Bool = false, isToday: Bool = true) -> SessionClock.State {
        SessionClock.state(record: record, hasSession: hasSession, finished: finished, isToday: isToday, now: now)
    }

    func testRunsForTodaysOpenWorkout() {
        let start = now.addingTimeInterval(-42 * 60)
        XCTAssertEqual(state(Record(since: start)), .running(since: start, counted: 0))
        XCTAssertEqual(SessionClock.elapsed(since: start, now: now), 42 * 60)
        XCTAssertEqual(SessionClock.elapsed(since: start, counted: 300, now: now), 47 * 60)
    }

    func testHiddenWhenNoWorkoutFinishedOrAnotherDay() {
        let record = Record(since: now.addingTimeInterval(-600))
        XCTAssertEqual(state(record, hasSession: false), .hidden)
        XCTAssertEqual(state(record, finished: true), .hidden)
        XCTAssertEqual(state(record, isToday: false), .hidden)
        XCTAssertEqual(state(Record(since: nil, counted: 600), finished: true), .hidden)
    }

    func testUnknownOrStaleClockAsksToStart() {
        XCTAssertEqual(state(nil), .notStarted)
        XCTAssertEqual(state(Record(since: now.addingTimeInterval(-7 * 3600))), .notStarted)
        XCTAssertEqual(state(Record(since: now.addingTimeInterval(3600))), .notStarted)
        XCTAssertEqual(state(Record(since: nil, counted: 7 * 3600)), .notStarted)
    }

    func testPausedClockKeepsItsTime() {
        XCTAssertEqual(state(Record(since: nil, counted: 754)), .paused(elapsed: 754))
    }

    func testPauseAndResumeSkipTheTimeInBetween() {
        let started = Record(since: now.addingTimeInterval(-600))
        let paused = started.paused(now: now)
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.counted, 600)
        XCTAssertEqual(paused.elapsed(now: now.addingTimeInterval(3600)), 600, "a paused clock doesn't count")
        XCTAssertEqual(paused.paused(now: now.addingTimeInterval(60)), paused, "pausing twice changes nothing")

        let back = now.addingTimeInterval(3600)
        let resumed = paused.resumed(now: back)
        XCTAssertEqual(resumed, Record(since: back, counted: 600))
        XCTAssertEqual(resumed.elapsed(now: back.addingTimeInterval(120)), 720, "the hour away is left out")
        XCTAssertEqual(resumed.resumed(now: back.addingTimeInterval(60)), resumed, "resuming a running clock changes nothing")
    }

    func testLoggingASetStartsOrResumesTheClock() {
        XCTAssertEqual(Record.afterSetLogged(nil, now: now), Record(since: now.addingTimeInterval(-60)),
                       "never started: counts from a minute back")
        XCTAssertEqual(Record.afterSetLogged(Record(since: nil, counted: 300), now: now), Record(since: now, counted: 300))
        let running = Record(since: now.addingTimeInterval(-900), counted: 120)
        XCTAssertEqual(Record.afterSetLogged(running, now: now), running)
    }

    func testRecordSurvivesStorage() throws {
        let record = Record(since: now, counted: 125)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(Record.self, from: data), record)
        let paused = try JSONEncoder().encode(Record(since: nil, counted: 60))
        XCTAssertEqual(try JSONDecoder().decode(Record.self, from: paused), Record(since: nil, counted: 60))
    }

    func testElapsedNeverNegative() {
        XCTAssertEqual(SessionClock.elapsed(since: now.addingTimeInterval(30), now: now), 0)
        XCTAssertEqual(Record(since: now.addingTimeInterval(30)).elapsed(now: now), 0)
    }

    func testClockFormat() {
        XCTAssertEqual(Fmt.clock(0), "0:00")
        XCTAssertEqual(Fmt.clock(307), "5:07")
        XCTAssertEqual(Fmt.clock(2533), "42:13")
        XCTAssertEqual(Fmt.clock(3909), "1:05:09")
        XCTAssertEqual(Fmt.clock(-5), "0:00")
    }
}
