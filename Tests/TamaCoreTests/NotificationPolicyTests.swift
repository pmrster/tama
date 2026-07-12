import XCTest
@testable import TamaCore

final class NotificationPolicyTests: XCTestCase {
    private let t0 = ISO8601DateFormatter.shared.date(from: "2026-07-07T10:00:00.000Z")!

    private func session(last: Date, ctxTokens: Int = 0, ctxWindow: Int = 0,
                         id: String = "s1") -> SessionInfo {
        SessionInfo(provider: .claudeCode, project: "tama", folder: "/x/tama",
                    lastActivity: last, contextTokens: ctxTokens, contextWindow: ctxWindow,
                    sessionId: id)
    }

    func test_agentQuiet_fires_once_after_observed_streaming_goes_silent() {
        var p = NotificationPolicy()
        let last = t0
        // Observed while streaming (quiet < threshold) → arms the rule.
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0), [])
        // 4 minutes later, same lastActivity → quiet ≥ 180s → one event.
        let e = p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(240))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.first?.kind, .agentQuiet)
        // Again later: no re-fire while still quiet.
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(300)), [])
    }

    func test_agentQuiet_does_not_fire_for_sessions_never_seen_streaming() {
        var p = NotificationPolicy()
        // First sighting is ALREADY 10 min quiet (e.g. app launch) → must not fire.
        let last = t0.addingTimeInterval(-600)
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0), [])
    }

    func test_agentQuiet_rearms_after_new_activity() {
        var p = NotificationPolicy()
        var last = t0
        _ = p.evaluate(sessions: [session(last: last)], now: t0)
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(240)).count, 1)
        // Session writes again → observed streaming again → quiet again → second event.
        last = t0.addingTimeInterval(300)
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(310)), [])
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(540)).count, 1)
    }

    func test_agentQuiet_silent_once_session_ages_out_of_active_window() {
        var p = NotificationPolicy()
        let last = t0
        _ = p.evaluate(sessions: [session(last: last)], now: t0)
        // 16 min quiet — outside the 15-min active window → treated as ended, no event.
        XCTAssertEqual(p.evaluate(sessions: [session(last: last)], now: t0.addingTimeInterval(960)), [])
    }

    func test_contextHigh_fires_once_with_hysteresis_rearm() {
        var p = NotificationPolicy()
        func s(_ tokens: Int) -> SessionInfo {
            session(last: t0, ctxTokens: tokens, ctxWindow: 100_000)
        }
        XCTAssertEqual(p.evaluate(sessions: [s(50_000)], now: t0), [])            // 50%
        let e = p.evaluate(sessions: [s(90_000)], now: t0.addingTimeInterval(7))  // 90% → fire
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.first?.kind, .contextHigh)
        XCTAssertEqual(p.evaluate(sessions: [s(95_000)], now: t0.addingTimeInterval(14)), []) // still high
        XCTAssertEqual(p.evaluate(sessions: [s(80_000)], now: t0.addingTimeInterval(21)), []) // 80% — between rearm and fire
        XCTAssertEqual(p.evaluate(sessions: [s(50_000)], now: t0.addingTimeInterval(28)), []) // < 75% → rearmed
        XCTAssertEqual(p.evaluate(sessions: [s(90_000)], now: t0.addingTimeInterval(35)).count, 1)
    }

    func test_vanished_sessions_drop_their_state() {
        var p = NotificationPolicy()
        _ = p.evaluate(sessions: [session(last: t0)], now: t0)
        _ = p.evaluate(sessions: [], now: t0.addingTimeInterval(60))   // session gone
        // Re-appears already quiet → fresh state → must not fire.
        XCTAssertEqual(p.evaluate(sessions: [session(last: t0)], now: t0.addingTimeInterval(300)), [])
    }
}
