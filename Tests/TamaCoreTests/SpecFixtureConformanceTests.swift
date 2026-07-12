import XCTest
@testable import TamaCore

/// Proves the canonical fixtures in spec/fixtures/ against the reference (Swift)
/// implementation. The C# suite asserts the same expected.json from the same files —
/// this is what keeps the two implementations in lockstep.
final class SpecFixtureConformanceTests: XCTestCase {
    // Tests/TamaCoreTests/ThisFile.swift → repo root is three levels up.
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("spec/fixtures")

    private struct Expected: Decodable {
        struct Session: Decodable {
            let folder: String; let project: String?
            let tokens: Int?; let cacheTokens: Int?
            let contextTokens: Int?; let contextWindow: Int?
            let model: String?; let sessionId: String?
            let title: String?; let messages: Int?
            let lastActivityEpochSeconds: Double?
        }
        let scanNow: String
        let claude: Session; let codex: Session
        let gemini: Session; let antigravity: Session
    }

    private func loadExpected() throws -> Expected {
        let data = try Data(contentsOf: Self.fixturesDir.appendingPathComponent("expected.json"))
        return try JSONDecoder().decode(Expected.self, from: data)
    }

    /// Copies spec/fixtures into a temp tree shaped like the real log roots and pins every
    /// file's mtime to `now` so the "today" window always matches, whatever day the suite runs.
    private func makeRoots(now: Date) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("spec-conf-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["claude", "codex", "gemini", "antigravity"] {
            try fm.copyItem(at: Self.fixturesDir.appendingPathComponent(name),
                            to: root.appendingPathComponent(name))
        }
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let f as URL in files {
                try? fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path)
            }
        }
        return root
    }

    func test_fixtures_match_expected_values() throws {
        let expected = try loadExpected()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: expected.scanNow))
        let root = try makeRoots(now: now)
        defer { try? FileManager.default.removeItem(at: root) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            geminiTmpDir: root.appendingPathComponent("gemini"),
            antigravityHistoryFile: root.appendingPathComponent("antigravity/history.jsonl"),
            now: { now }, calendar: cal)
        let sessions = reader.scan().sessions
        XCTAssertEqual(sessions.count, 4)

        let claude = try XCTUnwrap(sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(claude.folder, expected.claude.folder)
        XCTAssertEqual(claude.project, expected.claude.project)
        XCTAssertEqual(claude.tokens, expected.claude.tokens)
        XCTAssertEqual(claude.cacheTokens, expected.claude.cacheTokens)
        XCTAssertEqual(claude.contextTokens, expected.claude.contextTokens)
        XCTAssertEqual(claude.contextWindow, expected.claude.contextWindow)
        XCTAssertEqual(claude.model, expected.claude.model)
        XCTAssertEqual(claude.sessionId, expected.claude.sessionId)
        XCTAssertEqual(claude.title, expected.claude.title)
        XCTAssertEqual(claude.messages, expected.claude.messages)

        let codex = try XCTUnwrap(sessions.first { $0.provider == .codex })
        XCTAssertEqual(codex.folder, expected.codex.folder)
        XCTAssertEqual(codex.project, expected.codex.project)
        XCTAssertEqual(codex.tokens, expected.codex.tokens)
        XCTAssertEqual(codex.cacheTokens, expected.codex.cacheTokens)
        XCTAssertEqual(codex.contextTokens, expected.codex.contextTokens)
        XCTAssertEqual(codex.contextWindow, expected.codex.contextWindow)
        XCTAssertEqual(codex.model, expected.codex.model)
        XCTAssertEqual(codex.sessionId, expected.codex.sessionId)
        XCTAssertEqual(codex.title, expected.codex.title)
        XCTAssertEqual(codex.messages, expected.codex.messages)

        let gemini = try XCTUnwrap(sessions.first { $0.provider == .gemini })
        XCTAssertEqual(gemini.folder, expected.gemini.folder)

        let anti = try XCTUnwrap(sessions.first { $0.provider == .antigravity })
        XCTAssertEqual(anti.folder, expected.antigravity.folder)
        let epoch = try XCTUnwrap(expected.antigravity.lastActivityEpochSeconds)
        XCTAssertEqual(anti.lastActivity, Date(timeIntervalSince1970: epoch))
    }

    /// Pins the reference truncation unit: the 80-char cap counts extended grapheme clusters
    /// (Swift `String.count`), not UTF-16 code units. "🐈" is one user-perceived character but a
    /// UTF-16 surrogate pair, so 81 of them is grapheme-length 81 (UTF-16 length 162) — the C#
    /// port must match this by counting text elements, not slicing by UTF-16 index.
    func test_userPrompt_caps_by_grapheme_cluster_not_utf16_unit_for_emoji() {
        let cats81 = String(repeating: "🐈", count: 81)
        let cats80 = String(repeating: "🐈", count: 80)
        XCTAssertEqual(ActiveSessionsReader.userPrompt(["content": cats81]), cats80 + "…")
        XCTAssertEqual(ActiveSessionsReader.userPrompt(["content": cats80]), cats80)
    }

    func test_ollama_fixture_matches_expected_values() throws {
        let logURL = Self.fixturesDir.appendingPathComponent("ollama/server.log")
        let data = try Data(contentsOf: Self.fixturesDir.appendingPathComponent("expected.json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected = try XCTUnwrap(root["ollama"] as? [String: Any])
        let expectedModels = try XCTUnwrap(expected["models"] as? [[String: Any]])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let status = try XCTUnwrap(OllamaReader(logURL: logURL, calendar: utc).read())
        XCTAssertEqual(status.models.count, expectedModels.count)

        for (model, exp) in zip(status.models, expectedModels) {
            XCTAssertEqual(model.model, exp["model"] as? String)
            XCTAssertEqual(model.current, exp["current"] as? Bool)
            XCTAssertEqual(model.busy, exp["busy"] as? Bool)
            XCTAssertEqual(model.contextWindow, exp["contextWindow"] as? Int)
            XCTAssertEqual(model.contextTokens, exp["contextTokens"] as? Int)
            XCTAssertEqual(model.tokensPerSecond, exp["tokensPerSecond"] as? Double)
            XCTAssertEqual(try XCTUnwrap(model.lastLatency), try XCTUnwrap(exp["lastLatencySeconds"] as? Double), accuracy: 0.001)
            XCTAssertEqual(model.kind.rawValue, exp["kind"] as? String)
            XCTAssertEqual(model.requestCount, exp["requestCount"] as? Int)
            XCTAssertEqual(try XCTUnwrap(model.lastActivity).timeIntervalSince1970,
                           Double(try XCTUnwrap(exp["lastActivityEpochSeconds"] as? Int)), accuracy: 0.5)
        }
    }
}
