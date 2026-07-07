import XCTest
import TamaCore

private struct MockScanner: ActivityScanning {
    let activity: Activity
    func scan() -> Activity { activity }
}

@MainActor
final class AgentMonitorTests: XCTestCase {
    func test_refresh_publishes_active_sessions_and_totals() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let recent = fixed.addingTimeInterval(-120)    // 2 min ago -> active
        let stale = fixed.addingTimeInterval(-3600)    // 1 h ago -> idle
        let sessions = [
            SessionInfo(provider: .claudeCode, project: "a", folder: "/a", lastActivity: recent, tokens: 500, model: "claude-opus-4-8"),
            SessionInfo(provider: .codex, project: "b", folder: "/b", lastActivity: stale, tokens: 100, model: "gpt-5"),
        ]
        let activity = Activity(sessions: sessions, totals: [.claudeCode: 500, .codex: 100])
        let monitor = AgentMonitor(reader: MockScanner(activity: activity), now: { fixed }, runsInBackground: false)
        monitor.refresh()

        XCTAssertEqual(monitor.state.activeSessions.count, 2)
        XCTAssertEqual(monitor.state.usage[.claudeCode]?.todayTokens, 500)
        XCTAssertEqual(monitor.state.usage[.codex]?.todayTokens, 100)
        XCTAssertEqual(monitor.state.lastUpdated, fixed)
        XCTAssertTrue(monitor.isActive(sessions[0]))
        XCTAssertFalse(monitor.isActive(sessions[1]))
        XCTAssertEqual(monitor.activeCount(), 1)
        XCTAssertEqual(monitor.activeCount(for: .claudeCode), 1)
        XCTAssertEqual(monitor.activeCount(for: .codex), 0)
        XCTAssertEqual(monitor.activeSessions(for: .claudeCode).count, 1)
    }

    func test_refresh_computes_today_cost_from_breakdowns() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let est = CostEstimator(rates: [.claudeCode: Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)])
        let activity = Activity(sessions: [], breakdowns: [.claudeCode: TokenBreakdown(input: 1_000_000)])
        let monitor = AgentMonitor(reader: MockScanner(activity: activity), now: { fixed },
                                   runsInBackground: false, estimator: est)
        monitor.refresh()
        XCTAssertEqual(monitor.state.usage[.claudeCode]?.todayCost ?? -1, 3.0, accuracy: 0.0001)
        XCTAssertEqual(monitor.state.usage[.claudeCode]?.todayTokens, 1_000_000)
    }

    func test_cost_of_session_uses_estimator() {
        let est = CostEstimator(rates: [.codex: Rates(input: 2.5, output: 10, cacheRead: 0.25, cacheWrite: 2.5)])
        let monitor = AgentMonitor(reader: MockScanner(activity: .empty), now: { Date() },
                                   runsInBackground: false, estimator: est)
        let s = SessionInfo(provider: .codex, project: "p", folder: "/p", lastActivity: .distantPast,
                            breakdown: TokenBreakdown(output: 1_000_000))
        XCTAssertEqual(monitor.cost(s), 10.0, accuracy: 0.0001)
    }

    func test_today_cost_prices_each_model_separately() {
        // A project with both an Opus and a Haiku session: the provider total must price each
        // model's tokens at its own rate (Opus $5/M + Haiku $1/M = $6), not one flat rate.
        let est = CostEstimator(providerRates: [
            .claudeCode: ProviderRates(
                default: Rates(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),   // Opus
                models: ["haiku": Rates(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25)]),
        ])
        let activity = Activity(sessions: [], modelBreakdowns: [.claudeCode: [
            "claude-opus-4-8":  TokenBreakdown(input: 1_000_000),
            "claude-haiku-4-5": TokenBreakdown(input: 1_000_000),
        ]])
        let monitor = AgentMonitor(reader: MockScanner(activity: activity), now: { Date() },
                                   runsInBackground: false, estimator: est)
        monitor.refresh()
        XCTAssertEqual(monitor.state.usage[.claudeCode]?.todayCost ?? -1, 6.0, accuracy: 0.0001)
        XCTAssertEqual(monitor.state.usage[.claudeCode]?.todayTokens, 2_000_000)
    }

    func test_background_refresh_publishes_off_main_thread() {
        let monitor = AgentMonitor(reader: MockScanner(activity: Activity(sessions: [], totals: [.claudeCode: 42])),
                                   runsInBackground: true)
        let exp = expectation(description: "state published from background scan")
        monitor.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if monitor.state.usage[.claudeCode]?.todayTokens == 42 { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2)
    }

    func test_refresh_publishes_working_mood_for_active_session() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = SessionInfo(provider: .claudeCode, project: "tama-widget",
                                  folder: "/code/tama-widget",
                                  lastActivity: now.addingTimeInterval(-60))
        let scanner = MoodMonitorStubScanner(activity: Activity(sessions: [session], totals: [:]))
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMonitorMood-\(UUID().uuidString)", isDirectory: true)
        // Pre-seed lastSeenDay = now so greeting doesn't fire; we want to test working state.
        let store = CatStateStore(directory: tmp)
        store.save(CatState(lastSeenDay: now))
        let monitor = AgentMonitor(reader: scanner, now: { now }, runsInBackground: false,
                                   catStateStore: store)
        monitor.refresh()
        XCTAssertEqual(monitor.state.mood, .working(intensity: 1))
        try? FileManager.default.removeItem(at: tmp)
    }
}

/// Minimal `ActivityScanning` stub that returns a fixed `Activity`. A struct (not a class)
/// because `ActivityScanning: Sendable` — a value type with a `Sendable` `Activity` is
/// `Sendable` automatically; a class would need `@unchecked Sendable`.
private struct MoodMonitorStubScanner: ActivityScanning {
    let activity: Activity
    func scan() -> Activity { activity }
}

// MARK: - Usage history wiring

private final class HistoryStubReader: ActivityScanning, @unchecked Sendable {
    var activity = Activity.empty
    func scan() -> Activity { activity }
}

private final class HistoryStub: HistoryScanning, @unchecked Sendable {
    var days: [DayUsage] = []
    private(set) var calls = 0
    func scanHistory(days n: Int) -> [DayUsage] { calls += 1; return days }
}

@MainActor
final class AgentMonitorHistoryTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let t0 = ISO8601DateFormatter.shared.date(from: "2026-07-07T10:00:00.000Z")!

    private func makeMonitor(now: @escaping () -> Date, history: HistoryStub) -> AgentMonitor {
        AgentMonitor(reader: HistoryStubReader(), now: now, runsInBackground: false,
                     catStateStore: CatStateStore(directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("mon-\(UUID().uuidString)")),
                     historyReader: history, calendar: utc)
    }

    func test_history_scan_runs_once_then_waits_for_the_interval() {
        var now = t0
        let stub = HistoryStub()
        stub.days = [DayUsage(day: "2026-07-06",
                              models: [.claudeCode: ["opus": TokenBreakdown(input: 5)]])]
        let m = makeMonitor(now: { now }, history: stub)
        m.refresh()
        XCTAssertEqual(stub.calls, 1)
        XCTAssertTrue(m.state.history.contains { $0.day == "2026-07-06" })
        m.refresh()                                   // same instant — not due again
        XCTAssertEqual(stub.calls, 1)
        now = t0.addingTimeInterval(3601)             // past the hourly interval
        m.refresh()
        XCTAssertEqual(stub.calls, 2)
    }

    func test_day_rollover_triggers_rescan_before_the_interval() {
        var now = ISO8601DateFormatter.shared.date(from: "2026-07-07T23:59:00.000Z")!
        let stub = HistoryStub()
        let m = makeMonitor(now: { now }, history: stub)
        m.refresh()
        XCTAssertEqual(stub.calls, 1)
        now = now.addingTimeInterval(120)             // 00:01 next day — only 2 min later
        m.refresh()
        XCTAssertEqual(stub.calls, 2)
    }

    func test_published_history_always_carries_live_today_entry() {
        let stub = HistoryStub()
        stub.days = [DayUsage(day: "2026-07-06")]
        let m = makeMonitor(now: { self.t0 }, history: stub)
        m.refresh()
        XCTAssertEqual(m.state.history.last?.day, "2026-07-07")   // live today appended
    }

    func test_no_history_reader_publishes_empty_history() {
        let m = AgentMonitor(reader: HistoryStubReader(), now: { self.t0 }, runsInBackground: false,
                             catStateStore: CatStateStore(directory: FileManager.default.temporaryDirectory
                                .appendingPathComponent("mon-\(UUID().uuidString)")),
                             calendar: utc)
        m.refresh()
        XCTAssertEqual(m.state.history, [])
    }
}
