import XCTest
import TamaCore

final class QuotaReaderTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func date(_ s: String) -> Date { ISO8601DateFormatter.shared.date(from: s)! }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quota-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: model

    func test_window_is_expired_once_its_reset_time_has_passed() {
        let w = QuotaWindow(kind: .weekly, usedPercent: 40, resetsAt: date("2026-08-21T18:00:00.000Z"))
        XCTAssertFalse(w.isExpired(at: date("2026-08-21T17:59:00.000Z")))
        XCTAssertTrue(w.isExpired(at: date("2026-08-21T18:00:01.000Z")))
        XCTAssertFalse(QuotaWindow(kind: .session, usedPercent: 0, resetsAt: nil).isExpired(at: .distantFuture),
                       "no reset time → can't be called expired")
    }

    func test_used_percent_is_clamped_to_0_100() {
        XCTAssertEqual(QuotaWindow(kind: .session, usedPercent: 140, resetsAt: nil).usedPercent, 100)
        XCTAssertEqual(QuotaWindow(kind: .session, usedPercent: -3, resetsAt: nil).usedPercent, 0)
        XCTAssertEqual(QuotaWindow(kind: .session, usedPercent: 46, resetsAt: nil).remainingPercent, 54)
    }

    func test_plan_names_are_prettified() {
        XCTAssertEqual(AccountQuota.prettyPlan(codex: "plus"), "Plus")
        XCTAssertEqual(AccountQuota.prettyPlan(codex: "pro"), "Pro")
        XCTAssertEqual(AccountQuota.prettyPlan(claudeOrgType: "claude_max", tier: "default_claude_max_5x"), "Max 5x")
        XCTAssertEqual(AccountQuota.prettyPlan(claudeOrgType: "claude_max", tier: "default_claude_max_20x"), "Max 20x")
        XCTAssertEqual(AccountQuota.prettyPlan(claudeOrgType: "claude_pro", tier: nil), "Pro")
        XCTAssertEqual(AccountQuota.prettyPlan(claudeOrgType: "claude_team", tier: nil), "Team")
        XCTAssertNil(AccountQuota.prettyPlan(claudeOrgType: nil, tier: nil))
    }

    // MARK: Codex

    private func codexLine(ts: String, primaryMinutes: Int, primaryUsed: Double, primaryResets: Int,
                           secondary: String = "null", plan: String = "plus") -> String {
        "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null,"
        + "\"rate_limits\":{\"limit_id\":\"codex\",\"limit_name\":null,"
        + "\"primary\":{\"used_percent\":\(primaryUsed),\"window_minutes\":\(primaryMinutes),\"resets_at\":\(primaryResets)},"
        + "\"secondary\":\(secondary),\"credits\":{\"has_credits\":false,\"unlimited\":false,\"balance\":\"0\"},"
        + "\"plan_type\":\"\(plan)\",\"rate_limit_reached_type\":null}}}"
    }

    func test_codex_quota_comes_from_the_last_rate_limits_event_of_the_newest_rollout() throws {
        let root = try makeRoot()
        let day = root.appendingPathComponent("sessions/2026/08/22")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let lines = [
            codexLine(ts: "2026-08-22T00:01:00.000Z", primaryMinutes: 10080, primaryUsed: 40, primaryResets: 1787930295),
            "{\"timestamp\":\"2026-08-22T00:02:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\"}}",
            codexLine(ts: "2026-08-22T00:07:47.666Z", primaryMinutes: 10080, primaryUsed: 46, primaryResets: 1787930295,
                      secondary: "{\"used_percent\":12.5,\"window_minutes\":300,\"resets_at\":1787810000}"),
        ]
        try lines.joined(separator: "\n").write(to: day.appendingPathComponent("rollout-2026-08-22T00-00-00-aaaa.jsonl"),
                                                atomically: true, encoding: .utf8)

        let reader = QuotaReader(roots: [AccountRoot(provider: .codex, label: nil, root: root)],
                                 now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let quotas = reader.scanQuotas()
        XCTAssertEqual(quotas.count, 1)
        let q = try XCTUnwrap(quotas.first)
        XCTAssertEqual(q.provider, .codex)
        XCTAssertNil(q.label)
        XCTAssertEqual(q.plan, "Plus")
        XCTAssertEqual(q.source, .codexLog)
        XCTAssertEqual(q.fetchedAt, date("2026-08-22T00:07:47.666Z"))
        XCTAssertEqual(q.windows, [
            QuotaWindow(kind: .session, usedPercent: 12.5, resetsAt: Date(timeIntervalSince1970: 1787810000)),
            QuotaWindow(kind: .weekly, usedPercent: 46, resetsAt: Date(timeIntervalSince1970: 1787930295)),
        ], "session window sorts before weekly regardless of primary/secondary order")
        try? FileManager.default.removeItem(at: root)
    }

    func test_codex_prefers_the_most_recently_modified_rollout_and_skips_ones_without_limits() throws {
        let root = try makeRoot()
        let fm = FileManager.default
        let old = root.appendingPathComponent("sessions/2026/08/20")
        let new = root.appendingPathComponent("sessions/2026/08/22")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        let oldFile = old.appendingPathComponent("rollout-2026-08-20T00-00-00-old.jsonl")
        let newFile = new.appendingPathComponent("rollout-2026-08-22T00-00-00-new.jsonl")
        let newest = new.appendingPathComponent("rollout-2026-08-22T11-00-00-nolimits.jsonl")
        try codexLine(ts: "2026-08-20T01:00:00.000Z", primaryMinutes: 10080, primaryUsed: 10, primaryResets: 1)
            .write(to: oldFile, atomically: true, encoding: .utf8)
        try codexLine(ts: "2026-08-22T01:00:00.000Z", primaryMinutes: 10080, primaryUsed: 55, primaryResets: 2)
            .write(to: newFile, atomically: true, encoding: .utf8)
        // Newest by mtime, but carries no rate_limits yet (session just started) → fall through.
        try "{\"type\":\"session_meta\",\"payload\":{\"id\":\"x\"}}".write(to: newest, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: date("2026-08-20T01:00:00.000Z")], ofItemAtPath: oldFile.path)
        try fm.setAttributes([.modificationDate: date("2026-08-22T01:00:00.000Z")], ofItemAtPath: newFile.path)
        try fm.setAttributes([.modificationDate: date("2026-08-22T11:00:00.000Z")], ofItemAtPath: newest.path)

        let reader = QuotaReader(roots: [AccountRoot(provider: .codex, label: nil, root: root)],
                                 now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let q = try XCTUnwrap(reader.scanQuotas().first)
        XCTAssertEqual(q.windows.first?.usedPercent, 55)
        try? fm.removeItem(at: root)
    }

    func test_codex_without_any_limits_yields_nothing() throws {
        let root = try makeRoot()
        let day = root.appendingPathComponent("sessions/2026/08/22")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try "{\"type\":\"session_meta\",\"payload\":{\"id\":\"x\"}}\nnot json\n"
            .write(to: day.appendingPathComponent("rollout-2026-08-22T00-00-00-a.jsonl"), atomically: true, encoding: .utf8)
        let reader = QuotaReader(roots: [AccountRoot(provider: .codex, label: nil, root: root)],
                                 now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        XCTAssertTrue(reader.scanQuotas().isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Claude (cached /usage snapshot in .claude.json)

    private let claudeConfig = """
    {"numStartups":5,"oauthAccount":{"accountUuid":"fe7d259c-0000-4000-8000-000000000001","emailAddress":"dev@example.com",\
    "organizationName":"Example","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"},\
    "projects":{"/Users/x/p":{"history":[{"display":"secret prompt"}]}},\
    "cachedUsageUtilization":{"fetchedAtMs":1787329931540,"accountUuid":"fe7d259c-0000-4000-8000-000000000001",\
    "utilization":{"five_hour":{"utilization":23,"resets_at":"2026-08-21T20:00:00.123456+00:00"},\
    "seven_day":{"utilization":2.5,"resets_at":"2026-08-21T18:00:00.464148+00:00"},\
    "seven_day_opus":{"utilization":7,"resets_at":"2026-08-21T18:00:00.464148+00:00"},\
    "seven_day_sonnet":null,"extra_usage":{"is_enabled":false}}}}
    """

    func test_claude_quota_comes_from_the_cached_utilization_in_claude_json() throws {
        let root = try makeRoot()
        let cfg = root.appendingPathComponent(".claude.json")
        try claudeConfig.write(to: cfg, atomically: true, encoding: .utf8)
        let reader = QuotaReader(roots: [AccountRoot(provider: .claudeCode, label: nil, root: root, configFile: cfg)],
                                 now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let q = try XCTUnwrap(reader.scanQuotas().first)
        XCTAssertEqual(q.provider, .claudeCode)
        XCTAssertEqual(q.source, .claudeConfigCache)
        XCTAssertEqual(q.identity, "dev@example.com")
        XCTAssertEqual(q.plan, "Max 5x")
        XCTAssertEqual(q.accountKey, "fe7d259c-0000-4000-8000-000000000001")
        XCTAssertEqual(q.fetchedAt, Date(timeIntervalSince1970: 1787329931.540))
        XCTAssertEqual(q.windows, [
            QuotaWindow(kind: .session, usedPercent: 23, resetsAt: date("2026-08-21T20:00:00.123Z")),
            QuotaWindow(kind: .weekly, usedPercent: 2.5, resetsAt: date("2026-08-21T18:00:00.464Z")),
            QuotaWindow(kind: .scoped("Opus"), usedPercent: 7, resetsAt: date("2026-08-21T18:00:00.464Z")),
        ])
        try? FileManager.default.removeItem(at: root)
    }

    func test_claude_quota_is_skipped_when_the_config_is_missing_or_malformed() throws {
        let root = try makeRoot()
        let cfg = root.appendingPathComponent(".claude.json")
        let missing = QuotaReader(roots: [AccountRoot(provider: .claudeCode, label: nil, root: root, configFile: cfg)],
                                  now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        XCTAssertTrue(missing.scanQuotas().isEmpty)
        try "{\"oauthAccount\":{\"emailAddress\":\"a@b\"}".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertTrue(missing.scanQuotas().isEmpty, "truncated JSON → nothing, never a crash")
        try "{\"oauthAccount\":{\"emailAddress\":\"a@b\"}}".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertTrue(missing.scanQuotas().isEmpty, "an account with no cached utilization has nothing to show")
        try? FileManager.default.removeItem(at: root)
    }

    func test_quotas_are_ordered_by_provider_then_label() throws {
        let root = try makeRoot()
        let fm = FileManager.default
        let cfgA = root.appendingPathComponent("a/.claude.json"), cfgB = root.appendingPathComponent("b/.claude.json")
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        try claudeConfig.write(to: cfgA, atomically: true, encoding: .utf8)
        try claudeConfig.write(to: cfgB, atomically: true, encoding: .utf8)
        let day = root.appendingPathComponent("cx/sessions/2026/08/22")
        try fm.createDirectory(at: day, withIntermediateDirectories: true)
        try codexLine(ts: "2026-08-22T01:00:00.000Z", primaryMinutes: 10080, primaryUsed: 55, primaryResets: 2)
            .write(to: day.appendingPathComponent("rollout-2026-08-22T00-00-00-new.jsonl"), atomically: true, encoding: .utf8)
        let reader = QuotaReader(roots: [
            AccountRoot(provider: .codex, label: nil, root: root.appendingPathComponent("cx")),
            AccountRoot(provider: .claudeCode, label: "work", root: root.appendingPathComponent("b"), configFile: cfgB),
            AccountRoot(provider: .claudeCode, label: nil, root: root.appendingPathComponent("a"), configFile: cfgA),
        ], now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let qs = reader.scanQuotas()
        XCTAssertEqual(qs.map { "\($0.provider.rawValue):\($0.label ?? "-")" },
                       ["claudeCode:-", "claudeCode:work", "codex:-"])
        try? fm.removeItem(at: root)
    }
}

extension QuotaReaderTests {
    private func bridge(five: Double, fiveResets: Int, seven: Double, sevenResets: Int) -> String {
        "{\"workspace\":{\"current_dir\":\"/x\"},\"model\":{\"id\":\"claude\"},"
        + "\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(five),\"resets_at\":\(fiveResets)},"
        + "\"seven_day\":{\"used_percentage\":\(seven),\"resets_at\":\(sevenResets)}}}"
    }

    func test_statusline_bridge_supplies_live_windows_and_keeps_identity_from_the_config() throws {
        let root = try makeRoot()
        let cfg = root.appendingPathComponent(".claude.json")
        try claudeConfig.write(to: cfg, atomically: true, encoding: .utf8)   // fetchedAt = 2026-08-21 (stale)
        let sl = root.appendingPathComponent("statusline")
        try FileManager.default.createDirectory(at: sl, withIntermediateDirectories: true)
        let file = sl.appendingPathComponent("default.json")
        try bridge(five: 30, fiveResets: 1787900000, seven: 55, sevenResets: 1787930295)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date("2026-08-22T11:59:00.000Z")], ofItemAtPath: file.path)

        let reader = QuotaReader(roots: [AccountRoot(provider: .claudeCode, label: nil, root: root, configFile: cfg)],
                                 statuslineDir: sl, now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let q = try XCTUnwrap(reader.scanQuotas().first)
        XCTAssertEqual(q.source, .claudeStatusline, "the fresh bridge wins over the stale cache")
        XCTAssertEqual(q.identity, "dev@example.com", "identity still comes from .claude.json")
        XCTAssertEqual(q.plan, "Max 5x")
        XCTAssertEqual(q.fetchedAt, date("2026-08-22T11:59:00.000Z"))
        XCTAssertEqual(q.windows, [
            QuotaWindow(kind: .session, usedPercent: 30, resetsAt: Date(timeIntervalSince1970: 1787900000)),
            QuotaWindow(kind: .weekly, usedPercent: 55, resetsAt: Date(timeIntervalSince1970: 1787930295)),
        ])
        try? FileManager.default.removeItem(at: root)
    }

    func test_stale_bridge_does_not_override_a_fresher_cache() throws {
        let root = try makeRoot()
        let cfg = root.appendingPathComponent(".claude.json")
        // Cache fetched now; bridge is a week old → cache wins.
        let freshCache = claudeConfig.replacingOccurrences(of: "\"fetchedAtMs\":1787329931540",
                                                           with: "\"fetchedAtMs\":1787486400000")   // 2026-08-23
        try freshCache.write(to: cfg, atomically: true, encoding: .utf8)
        let sl = root.appendingPathComponent("statusline")
        try FileManager.default.createDirectory(at: sl, withIntermediateDirectories: true)
        let file = sl.appendingPathComponent("default.json")
        try bridge(five: 30, fiveResets: 1, seven: 55, sevenResets: 2).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date("2026-08-15T00:00:00.000Z")], ofItemAtPath: file.path)
        let reader = QuotaReader(roots: [AccountRoot(provider: .claudeCode, label: nil, root: root, configFile: cfg)],
                                 statuslineDir: sl, now: { self.date("2026-08-23T12:00:00.000Z") }, calendar: cal)
        let q = try XCTUnwrap(reader.scanQuotas().first)
        XCTAssertEqual(q.source, .claudeConfigCache)
        try? FileManager.default.removeItem(at: root)
    }

    func test_bridge_matches_account_by_label() throws {
        let root = try makeRoot()
        let cfg = root.appendingPathComponent(".claude.json")
        try claudeConfig.write(to: cfg, atomically: true, encoding: .utf8)
        let sl = root.appendingPathComponent("statusline")
        try FileManager.default.createDirectory(at: sl, withIntermediateDirectories: true)
        // A bridge file named for a DIFFERENT label must not attach to this default account.
        let other = sl.appendingPathComponent("work.json")
        try bridge(five: 99, fiveResets: 1, seven: 99, sevenResets: 2).write(to: other, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date("2026-08-22T11:59:00.000Z")], ofItemAtPath: other.path)
        let reader = QuotaReader(roots: [AccountRoot(provider: .claudeCode, label: nil, root: root, configFile: cfg)],
                                 statuslineDir: sl, now: { self.date("2026-08-22T12:00:00.000Z") }, calendar: cal)
        let q = try XCTUnwrap(reader.scanQuotas().first)
        XCTAssertEqual(q.source, .claudeConfigCache, "a mismatched-label bridge file is ignored for this account")
        try? FileManager.default.removeItem(at: root)
    }
}
