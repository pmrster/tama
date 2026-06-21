import XCTest
import TamaCore

final class CodexReaderTests: XCTestCase {
    func test_takes_last_cumulative_usage_per_session() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        let dayDir = root.appendingPathComponent("2026/06/19")
        try fm.createDirectory(at: dayDir, withIntermediateDirectories: true)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!

        func tokenLine(_ input: Int, _ cached: Int, _ output: Int) -> String {
            "{\"timestamp\":\"2026-06-19T02:18:24.883Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(input + output)}}}}"
        }
        // Two cumulative snapshots; the later (larger) one is the session total.
        let content = [tokenLine(1000, 200, 50), tokenLine(15586, 4992, 330)].joined(separator: "\n")
        let name = "rollout-2026-06-19T09-17-34-019eddab-58c2-7782-abd9-d1df0425c3d4.jsonl"
        try content.write(to: dayDir.appendingPathComponent(name), atomically: true, encoding: .utf8)

        let reader = CodexReader(sessionsDir: root, now: { now }, calendar: cal)
        let result = reader.read()
        // fresh input = 15586 - 4992 = 10594; cacheRead = 4992; output = 330
        XCTAssertEqual(result["019eddab"], TokenBreakdown(input: 10594, output: 330, cacheRead: 4992, cacheWrite: 0))
        XCTAssertEqual(result["019eddab"]?.total, 15916)
        try? fm.removeItem(at: root)
    }
}
