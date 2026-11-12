@testable import Gimmy
import XCTest

final class SessionClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunsForTodaysOpenWorkout() {
        let start = now.addingTimeInterval(-42 * 60)
        XCTAssertEqual(SessionClock.state(start: start, hasSession: true, finished: false, isToday: true, now: now),
                       .running(since: start))
        XCTAssertEqual(SessionClock.elapsed(since: start, now: now), 42 * 60)
    }

    func testHiddenWhenNoWorkoutFinishedOrAnotherDay() {
        let start = now.addingTimeInterval(-600)
        XCTAssertEqual(SessionClock.state(start: start, hasSession: false, finished: false, isToday: true, now: now), .hidden)
        XCTAssertEqual(SessionClock.state(start: start, hasSession: true, finished: true, isToday: true, now: now), .hidden)
        XCTAssertEqual(SessionClock.state(start: start, hasSession: true, finished: false, isToday: false, now: now), .hidden)
    }

    func testUnknownOrStaleStartAsksToStart() {
        XCTAssertEqual(SessionClock.state(start: nil, hasSession: true, finished: false, isToday: true, now: now), .notStarted)
        let stale = now.addingTimeInterval(-7 * 3600)
        XCTAssertEqual(SessionClock.state(start: stale, hasSession: true, finished: false, isToday: true, now: now), .notStarted)
        let future = now.addingTimeInterval(3600)
        XCTAssertEqual(SessionClock.state(start: future, hasSession: true, finished: false, isToday: true, now: now), .notStarted)
    }

    func testElapsedNeverNegative() {
        XCTAssertEqual(SessionClock.elapsed(since: now.addingTimeInterval(30), now: now), 0)
    }

    func testClockFormat() {
        XCTAssertEqual(Fmt.clock(0), "0:00")
        XCTAssertEqual(Fmt.clock(307), "5:07")
        XCTAssertEqual(Fmt.clock(2533), "42:13")
        XCTAssertEqual(Fmt.clock(3909), "1:05:09")
        XCTAssertEqual(Fmt.clock(-5), "0:00")
    }
}
