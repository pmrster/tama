import XCTest
import CryptoKit
import TamaCore

final class SafetyNoWriteTests: XCTestCase {
    private func snapshot(_ root: URL) -> [String: String] {
        var map: [String: String] = [:]
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return map }
        for case let url as URL in en {
            if let data = try? Data(contentsOf: url) {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                map[url.path] = digest
            }
        }
        return map
    }

    func test_readers_never_modify_the_filesystem() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("safety-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-x-p")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        let ollamaLogs = root.appendingPathComponent("ollama/logs")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)
        try fm.createDirectory(at: ollamaLogs, withIntermediateDirectories: true)
        try "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/p\",\"message\":{\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}"
            .write(to: claudeProj.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        try "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":1,\"cached_input_tokens\":0,\"output_tokens\":1,\"total_tokens\":2}}}}"
            .write(to: codexDay.appendingPathComponent("rollout-2026-06-19T09-00-00-aaaaaaaa-x.jsonl"), atomically: true, encoding: .utf8)
        try ("time=2026-06-22T18:36:56.556+07:00 msg=\"starting mlx runner subprocess\" model=qwen3.6:27b-mlx\n"
             + "slot update_slots: id  0 | task 0 | new prompt, n_ctx_slot = 32768, task.n_tokens = 100\n"
             + "srv  update_slots: all slots are idle\n")
            .write(to: ollamaLogs.appendingPathComponent("server.log"), atomically: true, encoding: .utf8)

        let before = snapshot(root)
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T10:00:00.000Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!

        _ = ClaudeReader(projectsDir: root.appendingPathComponent("claude"), now: { now }, calendar: cal).read()
        _ = CodexReader(sessionsDir: root.appendingPathComponent("codex"), now: { now }, calendar: cal).read()
        _ = ActiveSessionsReader(claudeProjectsDir: root.appendingPathComponent("claude"),
                                 codexSessionsDir: root.appendingPathComponent("codex"),
                                 now: { now }, calendar: cal).read()
        _ = OllamaReader(logURL: ollamaLogs.appendingPathComponent("server.log")).read()

        let after = snapshot(root)
        XCTAssertEqual(before, after, "readers must not add, remove, or modify any file")
        try? fm.removeItem(at: root)
    }

    func test_readers_ignore_symlinked_logs_and_project_dirs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("symlink-safety-\(UUID().uuidString)")
        let claudeRoot = root.appendingPathComponent("claude")
        let project = claudeRoot.appendingPathComponent("-Users-x-p")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)

        let validLog = """
        {"timestamp":"2026-06-19T09:00:00.000Z","cwd":"/Example/Code/p","message":{"usage":{"input_tokens":9,"output_tokens":1}}}
        """
        let outsideLog = outside.appendingPathComponent("outside.jsonl")
        try validLog.write(to: outsideLog, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: project.appendingPathComponent("linked.jsonl"), withDestinationURL: outsideLog)

        let linkedProject = claudeRoot.appendingPathComponent("-Users-x-linked")
        try fm.createSymbolicLink(at: linkedProject, withDestinationURL: outside)

        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T10:00:00.000Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!

        let claude = ClaudeReader(projectsDir: claudeRoot, now: { now }, calendar: cal).read()
        XCTAssertTrue(claude.isEmpty, "symlinked logs and project directories must not be followed")

        let activity = ActiveSessionsReader(claudeProjectsDir: claudeRoot,
                                            codexSessionsDir: root.appendingPathComponent("codex"),
                                            now: { now }, calendar: cal).read()
        XCTAssertTrue(activity.isEmpty, "active-session scan must not follow symlinked logs or directories")
        try? fm.removeItem(at: root)
    }

    func test_readers_ignore_oversized_log_files() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("oversize-safety-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-x-p")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)

        let hugeClaude = claudeProj.appendingPathComponent("huge.jsonl")
        let hugeCodex = codexDay.appendingPathComponent("rollout-2026-06-19T09-00-00-aaaaaaaa-x.jsonl")
        fm.createFile(atPath: hugeClaude.path, contents: nil)
        fm.createFile(atPath: hugeCodex.path, contents: nil)
        try FileHandle(forWritingTo: hugeClaude).truncate(atOffset: UInt64(129 * 1024 * 1024))
        try FileHandle(forWritingTo: hugeCodex).truncate(atOffset: UInt64(129 * 1024 * 1024))

        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T10:00:00.000Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertTrue(ClaudeReader(projectsDir: root.appendingPathComponent("claude"), now: { now }, calendar: cal).read().isEmpty)
        XCTAssertTrue(CodexReader(sessionsDir: root.appendingPathComponent("codex"), now: { now }, calendar: cal).read().isEmpty)
        XCTAssertTrue(ActiveSessionsReader(claudeProjectsDir: root.appendingPathComponent("claude"),
                                           codexSessionsDir: root.appendingPathComponent("codex"),
                                           now: { now }, calendar: cal).read().isEmpty)
        try? fm.removeItem(at: root)
    }
}
