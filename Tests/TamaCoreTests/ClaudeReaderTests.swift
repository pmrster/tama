import XCTest
import TamaCore

final class ClaudeReaderTests: XCTestCase {
    func test_sums_only_todays_lines_per_project() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)")
        let proj = root.appendingPathComponent("-Users-example-myproj")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T10:00:00.000Z")!
        let todayTS = "2026-06-19T09:00:00.000Z"
        let yesterdayTS = "2026-06-18T09:00:00.000Z"

        func line(_ ts: String, _ inTok: Int, _ outTok: Int) -> String {
            "{\"timestamp\":\"\(ts)\",\"cwd\":\"/Example/Code/myproj\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":\(inTok),\"output_tokens\":\(outTok),\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}}}"
        }
        let content = [line(todayTS, 100, 10), line(yesterdayTS, 9999, 9999)].joined(separator: "\n")
        let logFile = proj.appendingPathComponent("s.jsonl")
        try content.write(to: logFile, atomically: true, encoding: .utf8)
        // Stamp the file's mtime to the injected clock; the reader fast-skips files whose real
        // mtime isn't "today", which otherwise makes this fixture flaky across a midnight rollover.
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: logFile.path)

        let reader = ClaudeReader(projectsDir: root, now: { now })
        let result = reader.read()
        XCTAssertEqual(result["myproj"], TokenBreakdown(input: 100, output: 10, cacheRead: 5, cacheWrite: 2))
        try? fm.removeItem(at: root)
    }
}
