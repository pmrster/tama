import XCTest
@testable import TamaCore

final class UsageHistoryTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func test_dayKey_formats_local_day() {
        let d = ISO8601DateFormatter.shared.date(from: "2026-07-07T23:59:00.000Z")!
        XCTAssertEqual(UsageHistory.dayKey(d, calendar: utc), "2026-07-07")
        var bkk = Calendar(identifier: .gregorian)
        bkk.timeZone = TimeZone(identifier: "Asia/Bangkok")!   // UTC+7 → already next day
        XCTAssertEqual(UsageHistory.dayKey(d, calendar: bkk), "2026-07-08")
    }

    func test_sum_merges_models_and_projects_across_days() {
        let a = DayUsage(day: "2026-07-01",
                         models: [.claudeCode: ["opus": TokenBreakdown(input: 10, output: 5)]],
                         projects: [.claudeCode: ["tama": TokenBreakdown(input: 10, output: 5)]])
        let b = DayUsage(day: "2026-07-02",
                         models: [.claudeCode: ["opus": TokenBreakdown(input: 1)],
                                  .codex: ["gpt-5": TokenBreakdown(output: 2)]],
                         projects: [.claudeCode: ["tama": TokenBreakdown(input: 1)]])
        let s = DayUsage.sum([a, b], as: "2026-07-02")
        XCTAssertEqual(s.day, "2026-07-02")
        XCTAssertEqual(s.models[.claudeCode]?["opus"], TokenBreakdown(input: 11, output: 5))
        XCTAssertEqual(s.models[.codex]?["gpt-5"], TokenBreakdown(output: 2))
        XCTAssertEqual(s.projects[.claudeCode]?["tama"], TokenBreakdown(input: 11, output: 5))
        // 11+5 (merged opus) + 2 (codex gpt-5 output) = 18. (Brief listed 19; corrected — see task-1-report.md.)
        XCTAssertEqual(s.totalTokens, 18)
    }

    func test_rollup_filters_by_day_key_range_inclusive() {
        let days = ["2026-07-01", "2026-07-02", "2026-07-03"].map {
            DayUsage(day: $0, models: [.claudeCode: ["opus": TokenBreakdown(input: 1)]])
        }
        let h = UsageHistory(days: days)
        XCTAssertEqual(h.rollup(from: "2026-07-02", through: "2026-07-03").totalTokens, 2)
        XCTAssertEqual(h.rollup(from: "2026-07-01", through: "2026-07-03").totalTokens, 3)
        XCTAssertEqual(h.rollup(from: "2026-07-04", through: "2026-07-05").totalTokens, 0)
    }

    func test_topModel_is_largest_by_total_tokens() {
        let d = DayUsage(day: "2026-07-01",
                         models: [.claudeCode: ["opus": TokenBreakdown(input: 5)],
                                  .codex: ["gpt-5": TokenBreakdown(input: 50)]])
        let top = d.topModel()
        XCTAssertEqual(top?.provider, .codex)
        XCTAssertEqual(top?.model, "gpt-5")
    }

    func test_codable_round_trip_and_provider_keys_encode_as_raw_values() throws {
        let d = DayUsage(day: "2026-07-01",
                         models: [.claudeCode: ["opus": TokenBreakdown(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, cacheWrite1h: 1)]],
                         projects: [.claudeCode: ["tama": TokenBreakdown(input: 1)]])
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode([d])
        let decoded = try JSONDecoder().decode([DayUsage].self, from: data)
        XCTAssertEqual(decoded, [d])
        // File-format guard: provider dict keys must be raw values ("claudeCode"), not arrays.
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"claudeCode\""), "provider keys must encode as JSON object keys: \(json)")
    }
}
