import XCTest
@testable import TamaCore

final class HistoryReaderTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = ISO8601DateFormatter.shared.date(from: "2026-07-07T12:00:00.000Z")!

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude/-Users-x-p"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("codex/2026/07/05"),
                                                withIntermediateDirectories: true)
        return root
    }
    private func reader(_ root: URL) -> HistoryReader {
        HistoryReader(claudeProjectsDir: root.appendingPathComponent("claude"),
                      codexSessionsDir: root.appendingPathComponent("codex"),
                      now: { self.now }, calendar: utc)
    }

    func test_claude_usage_buckets_split_by_local_day_and_dedupe_by_message_id() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // One session spanning midnight; the second line repeats msg-2's usage (split content
        // blocks) and must be counted once; model is carried on the message.
        let log = """
        {"timestamp":"2026-07-05T23:30:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m1","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":1}}}
        {"timestamp":"2026-07-06T00:30:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m2","model":"claude-opus-4-8","usage":{"input_tokens":20,"output_tokens":2}}}
        {"timestamp":"2026-07-06T00:30:01.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m2","model":"claude-opus-4-8","usage":{"input_tokens":20,"output_tokens":2}}}
        """
        try log.write(to: root.appendingPathComponent("claude/-Users-x-p/s.jsonl"),
                      atomically: true, encoding: .utf8)
        let days = reader(root).scanHistory(days: 30).days
        let d5 = days.first { $0.day == "2026-07-05" }
        let d6 = days.first { $0.day == "2026-07-06" }
        XCTAssertEqual(d5?.models[.claudeCode]?["claude-opus-4-8"], TokenBreakdown(input: 10, output: 1))
        XCTAssertEqual(d6?.models[.claudeCode]?["claude-opus-4-8"], TokenBreakdown(input: 20, output: 2))
        XCTAssertEqual(d5?.projects[.claudeCode]?["p"], TokenBreakdown(input: 10, output: 1))
    }

    func test_codex_file_attributed_to_its_date_directory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = """
        {"type":"session_meta","payload":{"id":"abcd1234","cwd":"/x/q"}}
        {"type":"turn_context","payload":{"model":"gpt-5.3-codex"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":7}}}}
        """
        try log.write(to: root.appendingPathComponent("codex/2026/07/05/rollout-2026-07-05T09-00-00-abcd1234-x.jsonl"),
                      atomically: true, encoding: .utf8)
        let days = reader(root).scanHistory(days: 30).days
        let d5 = days.first { $0.day == "2026-07-05" }
        XCTAssertEqual(d5?.models[.codex]?["gpt-5.3-codex"],
                       TokenBreakdown(input: 60, output: 7, cacheRead: 40))
        XCTAssertEqual(d5?.projects[.codex]?["q"], TokenBreakdown(input: 60, output: 7, cacheRead: 40))
    }

    func test_days_outside_window_are_dropped() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Old bucket inside a file whose mtime is recent: line from 40 days ago must not appear.
        let log = """
        {"timestamp":"2026-05-28T10:00:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m1","usage":{"input_tokens":10}}}
        {"timestamp":"2026-07-07T10:00:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m2","usage":{"input_tokens":5}}}
        """
        try log.write(to: root.appendingPathComponent("claude/-Users-x-p/s.jsonl"),
                      atomically: true, encoding: .utf8)
        let scan = reader(root).scanHistory(days: 30)
        XCTAssertNil(scan.days.first { $0.day == "2026-05-28" })
        XCTAssertEqual(scan.days.first { $0.day == "2026-07-07" }?.totalTokens, 5)
        // The heatmap grid is window-clamped just like the day rollups: the 40-day-old turn
        // inside this recent-mtime file must NOT leak into it. 2026-07-07 is a Tuesday
        // (weekday 3) → cell (3-1)*24 + 10 = 58; only its 5 tokens count.
        XCTAssertEqual(scan.weekdayHour.reduce(0, +), 5, "out-of-window turn must not inflate the heatmap")
        XCTAssertEqual(scan.weekdayHour[58], 5)
    }

    func test_old_claude_files_by_mtime_are_skipped() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude/-Users-x-p/old.jsonl")
        try "{\"timestamp\":\"2026-07-01T10:00:00.000Z\",\"cwd\":\"/x/p\",\"type\":\"assistant\",\"message\":{\"id\":\"m1\",\"usage\":{\"input_tokens\":10}}}"
            .write(to: file, atomically: true, encoding: .utf8)
        // Backdate the file's mtime to before the 30-day window.
        try FileManager.default.setAttributes(
            [.modificationDate: ISO8601DateFormatter.shared.date(from: "2026-05-01T00:00:00.000Z")!],
            ofItemAtPath: file.path)
        XCTAssertTrue(reader(root).scanHistory(days: 30).days.isEmpty)
    }

    func test_scan_is_stable_across_repeat_calls() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "{\"timestamp\":\"2026-07-06T10:00:00.000Z\",\"cwd\":\"/x/p\",\"type\":\"assistant\",\"message\":{\"id\":\"m1\",\"usage\":{\"input_tokens\":10}}}"
            .write(to: root.appendingPathComponent("claude/-Users-x-p/s.jsonl"),
                   atomically: true, encoding: .utf8)
        let r = reader(root)
        let first = r.scanHistory(days: 30).days
        XCTAssertEqual(r.scanHistory(days: 30).days, first)   // cache hit path returns identical data
    }

    func test_claude_tokens_bucketed_into_weekday_hour_cells() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // 2026-07-06 is a Monday. 10:00 and 10:30 UTC → same cell (Mon, hour 10); 22:00 → (Mon, hour 22).
        let log = """
        {"timestamp":"2026-07-06T10:00:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":1}}}
        {"timestamp":"2026-07-06T10:30:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m2","usage":{"input_tokens":4,"output_tokens":0}}}
        {"timestamp":"2026-07-06T22:00:00.000Z","cwd":"/x/p","type":"assistant","message":{"id":"m3","usage":{"input_tokens":5,"output_tokens":0}}}
        """
        try log.write(to: root.appendingPathComponent("claude/-Users-x-p/s.jsonl"), atomically: true, encoding: .utf8)
        let scan = reader(root).scanHistory(days: 30)
        XCTAssertEqual(scan.weekdayHour.count, 168)
        // Monday = Calendar weekday 2 → row base (2-1)*24 = 24. Hour 10 → cell 34; hour 22 → cell 46.
        // m1 total 11 (10 in + 1 out) + m2 total 4 (4 in) = 15 in cell 34; m3 total 5 in cell 46.
        XCTAssertEqual(scan.weekdayHour[34], 15)
        XCTAssertEqual(scan.weekdayHour[46], 5)
        XCTAssertEqual(scan.weekdayHour.reduce(0, +), 20)
    }

    func test_codex_contributes_nothing_to_weekday_hour() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = """
        {"type":"session_meta","payload":{"id":"abcd1234","cwd":"/x/q"}}
        {"type":"turn_context","payload":{"model":"gpt-5.3-codex"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":7}}}}
        """
        try log.write(to: root.appendingPathComponent("codex/2026/07/05/rollout-2026-07-05T09-00-00-abcd1234-x.jsonl"),
                      atomically: true, encoding: .utf8)
        let scan = reader(root).scanHistory(days: 30)
        XCTAssertEqual(scan.weekdayHour.reduce(0, +), 0, "Codex has no per-turn hours → no heatmap contribution")
        XCTAssertEqual(scan.days.first?.day, "2026-07-05")   // but it still appears in day rollups
    }

    func test_days_still_returned_alongside_grid() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "{\"timestamp\":\"2026-07-06T10:00:00.000Z\",\"cwd\":\"/x/p\",\"type\":\"assistant\",\"message\":{\"id\":\"m1\",\"usage\":{\"input_tokens\":10}}}"
            .write(to: root.appendingPathComponent("claude/-Users-x-p/s.jsonl"), atomically: true, encoding: .utf8)
        let scan = reader(root).scanHistory(days: 30)
        XCTAssertEqual(scan.days.first { $0.day == "2026-07-06" }?.totalTokens, 10)
    }
}
