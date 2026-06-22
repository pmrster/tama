import XCTest
@testable import TamaCore

final class MoodEngineTests: XCTestCase {
    // Deterministic calendar: same-day comparisons must not depend on the test machine's zone.
    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return utcCalendar().date(from: c)!
    }

    private func session(lastActivity: Date) -> SessionInfo {
        SessionInfo(provider: .claudeCode, project: "tama-widget",
                    folder: "/code/tama-widget", lastActivity: lastActivity)
    }

    private func engine() -> MoodEngine {
        MoodEngine(activeWindow: 900, restWindow: 3600, calendar: utcCalendar())
    }

    func test_empty_activity_is_napping() {
        let e = engine()
        let (mood, _) = e.evaluate(activity: .empty, now: date(2026, 6, 22), state: .initial)
        XCTAssertEqual(mood, .napping)
    }

    func test_recent_session_within_active_window_is_working_with_intensity() {
        let e = engine()
        let now = date(2026, 6, 22, 12, 0)
        // Two sessions active in the last 15 min, plus the day already greeted.
        let activity = Activity(sessions: [
            session(lastActivity: now.addingTimeInterval(-60)),
            session(lastActivity: now.addingTimeInterval(-300)),
        ], totals: [:])
        let state = CatState(lastSeenDay: now)
        let (mood, _) = e.evaluate(activity: activity, now: now, state: state)
        XCTAssertEqual(mood, .working(intensity: 2))
    }

    func test_paused_within_rest_window_is_resting() {
        let e = engine()
        let now = date(2026, 6, 22, 12, 0)
        // 30 min ago: past activeWindow (15m), within restWindow (60m).
        let activity = Activity(sessions: [session(lastActivity: now.addingTimeInterval(-1800))], totals: [:])
        let (mood, _) = e.evaluate(activity: activity, now: now, state: CatState(lastSeenDay: now))
        XCTAssertEqual(mood, .resting)
    }

    func test_idle_beyond_rest_window_is_napping() {
        let e = engine()
        let now = date(2026, 6, 22, 12, 0)
        // 90 min ago: beyond restWindow.
        let activity = Activity(sessions: [session(lastActivity: now.addingTimeInterval(-5400))], totals: [:])
        let (mood, _) = e.evaluate(activity: activity, now: now, state: CatState(lastSeenDay: now))
        XCTAssertEqual(mood, .napping)
    }

    func test_active_window_boundary() {
        let e = engine()
        let now = date(2026, 6, 22, 12, 0)
        // 14:59 → still working; 15:01 → no longer working (resting).
        let working = Activity(sessions: [session(lastActivity: now.addingTimeInterval(-899))], totals: [:])
        let resting = Activity(sessions: [session(lastActivity: now.addingTimeInterval(-901))], totals: [:])
        XCTAssertEqual(e.evaluate(activity: working, now: now, state: CatState(lastSeenDay: now)).mood, .working(intensity: 1))
        XCTAssertEqual(e.evaluate(activity: resting, now: now, state: CatState(lastSeenDay: now)).mood, .resting)
    }

    func test_greeting_fires_once_on_new_day_then_yields_to_working() {
        let e = engine()
        let now = date(2026, 6, 22, 9, 0)
        let activity = Activity(sessions: [session(lastActivity: now.addingTimeInterval(-60))], totals: [:])

        // First scan of the day (lastSeenDay was yesterday) → greeting, state stamped to today.
        let first = e.evaluate(activity: activity, now: now, state: CatState(lastSeenDay: date(2026, 6, 21)))
        XCTAssertEqual(first.mood, .greeting)
        XCTAssertEqual(utcCalendar().isDate(first.state.lastSeenDay!, inSameDayAs: now), true)

        // Next scan, same day, using the returned state → working, not greeting again.
        let second = e.evaluate(activity: activity, now: now.addingTimeInterval(7), state: first.state)
        XCTAssertEqual(second.mood, .working(intensity: 1))
    }

    func test_greeting_does_not_fire_without_activity_today() {
        let e = engine()
        let now = date(2026, 6, 22, 9, 0)
        // Only stale activity from yesterday → no greeting, state unchanged (lastSeenDay stays nil).
        let activity = Activity(sessions: [session(lastActivity: date(2026, 6, 21, 23, 0))], totals: [:])
        let result = e.evaluate(activity: activity, now: now, state: .initial)
        XCTAssertNotEqual(result.mood, .greeting)
        XCTAssertNil(result.state.lastSeenDay)
    }
}
