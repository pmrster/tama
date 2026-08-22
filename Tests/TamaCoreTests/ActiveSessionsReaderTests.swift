import XCTest
import TamaCore

final class ActiveSessionsReaderTests: XCTestCase {
    func test_lists_claude_and_codex_sessions_with_project_and_folder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("active-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)

        // Claude: two turns. Cumulative = sum of both = (100+10+5+2)+(120+20+9000+1000) = 10257.
        // Context = the LAST turn's occupancy = input + cache + output = 120 + 9000 + 1000 + 20 = 10140.
        let claudeContent = [
            "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}}}",
            "{\"timestamp\":\"2026-06-19T09:05:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":120,\"output_tokens\":20,\"cache_read_input_tokens\":9000,\"cache_creation_input_tokens\":1000}}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try claudeContent.write(to: claudeFile, atomically: true, encoding: .utf8)
        // Codex: cwd in session_meta; model in turn_context; cumulative token_count -> 15586 + 330 = 15916.
        // last_token_usage.input_tokens (8000) = live context; model_context_window = 272000.
        let codexContent = [
            "{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab\",\"cwd\":\"/Example/Code/widget\"}}",
            "{\"timestamp\":\"2026-06-19T08:01:00.000Z\",\"type\":\"turn_context\",\"payload\":{\"cwd\":\"/Example/Code/widget\",\"model\":\"gpt-5-codex\"}}",
            "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":15586,\"cached_input_tokens\":4992,\"output_tokens\":330,\"total_tokens\":15916},\"last_token_usage\":{\"input_tokens\":8000,\"cached_input_tokens\":2000,\"output_tokens\":120,\"total_tokens\":8120},\"model_context_window\":272000}}}",
        ].joined(separator: "\n")
        let codexFile = codexDay.appendingPathComponent("rollout-2026-06-19T08-00-00-019eddab-x.jsonl")
        try codexContent.write(to: codexFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        // Pin the log mtimes to the fixture's clock so the scan's "today" window matches regardless
        // of the real date the suite runs on (the scan pre-filters files by mtime).
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: codexFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)

        let sessions = reader.read()
        XCTAssertEqual(sessions.count, 2)

        let claude = try XCTUnwrap(sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(claude.project, "myapp")
        XCTAssertEqual(claude.folder, "/Example/Code/myapp")
        XCTAssertEqual(claude.tokens, 10257)               // cumulative across both turns
        XCTAssertEqual(claude.contextTokens, 10140)        // last turn input + cache + output
        XCTAssertEqual(claude.contextWindow, 200_000)      // default Claude window
        XCTAssertEqual(claude.model, "claude-opus-4-8")

        let codex = try XCTUnwrap(sessions.first { $0.provider == .codex })
        XCTAssertEqual(codex.project, "widget")
        XCTAssertEqual(codex.folder, "/Example/Code/widget")
        XCTAssertEqual(codex.tokens, 15916)                // cumulative total_token_usage
        XCTAssertEqual(codex.contextTokens, 8120)          // last_token_usage input + output
        XCTAssertEqual(codex.contextWindow, 272_000)       // model_context_window from log
        XCTAssertEqual(codex.model, "gpt-5-codex")

        try? fm.removeItem(at: root)
    }

    func test_counts_messages_per_session() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("msg-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)

        // Claude /resume counts conversation messages = lines with type user/assistant.
        // 2 user (one a tool_result) + 2 assistant = 4.
        let claudeContent = [
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"role\":\"user\",\"content\":\"start\"}}",
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:01:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}",
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:02:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":12,\"output_tokens\":6,\"cache_read_input_tokens\":100}}}",
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:03:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"x\",\"content\":\"ok\"}]}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try claudeContent.write(to: claudeFile, atomically: true, encoding: .utf8)

        // Codex messages = `message` response-items with role user/assistant (developer/system
        // and the duplicated user_message/agent_message events are not counted). = 2.
        let codexContent = [
            "{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab\",\"cwd\":\"/Example/Code/widget\"}}",
            "{\"timestamp\":\"2026-06-19T08:01:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"developer\",\"content\":[{\"type\":\"input_text\",\"text\":\"sys\"}]}}",
            "{\"timestamp\":\"2026-06-19T08:02:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hello\"}]}}",
            "{\"timestamp\":\"2026-06-19T08:03:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"hi\"}]}}",
            "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"output_tokens\":10,\"total_tokens\":110}}}}",
        ].joined(separator: "\n")
        let codexFile = codexDay.appendingPathComponent("rollout-2026-06-19T08-00-00-019eddab-x.jsonl")
        try codexContent.write(to: codexFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: codexFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)

        let claude = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        XCTAssertEqual(claude.messages, 4)
        let codex = try XCTUnwrap(reader.read().first { $0.provider == .codex })
        XCTAssertEqual(codex.messages, 2)

        try? fm.removeItem(at: root)
    }

    /// Claude Code (v2.x) writes ONE assistant response as several jsonl lines — one per content
    /// block (thinking, text, each tool_use) — and repeats the SAME message-level `usage` on every
    /// line. Counting each line double-counts tokens (~2x, more on multi-block turns). The fix:
    /// count a response's usage and message ONCE per `message.id`. Also: `isMeta` user lines are
    /// injected metadata (e.g. an image-cache reference), not real messages — exclude them.
    func test_claude_dedupes_split_assistant_lines_by_message_id() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dedup-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        // One real prompt + one assistant reply that the log splits into a `thinking` line and a
        // `text` line — SAME message.id, IDENTICAL usage. Plus an isMeta user line (not a message).
        let usage = "\"usage\":{\"input_tokens\":16895,\"output_tokens\":603,\"cache_read_input_tokens\":15840,\"cache_creation_input_tokens\":5199}"
        let claudeContent = [
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"role\":\"user\",\"content\":\"why so many branches?\"}}",
            "{\"type\":\"user\",\"isMeta\":true,\"timestamp\":\"2026-06-19T09:00:01.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"role\":\"user\",\"content\":\"[Image: source: /cache/1.png]\"}}",
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:07.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"id\":\"msg_A\",\"model\":\"claude-opus-4-8\",\(usage)}}",
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:13.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"id\":\"msg_A\",\"model\":\"claude-opus-4-8\",\(usage)}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try claudeContent.write(to: claudeFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)

        let claude = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        // Usage counted ONCE, not summed across the two split lines.
        XCTAssertEqual(claude.tokens, 38537)            // 16895+603+15840+5199 (NOT doubled to 77074)
        XCTAssertEqual(claude.breakdown.input, 16895)
        XCTAssertEqual(claude.breakdown.output, 603)
        XCTAssertEqual(claude.breakdown.cacheRead, 15840)
        XCTAssertEqual(claude.breakdown.cacheWrite, 5199)
        XCTAssertEqual(claude.cacheTokens, 21039)       // read + write, once
        XCTAssertEqual(claude.freshTokens, 17498)       // input + output, once
        XCTAssertEqual(claude.contextTokens, 38537)     // last reply's occupancy, once
        // 1 real user prompt + 1 assistant reply. The isMeta line and the split line don't add.
        XCTAssertEqual(claude.messages, 2)

        try? fm.removeItem(at: root)
    }

    /// Claude writes to the 1-hour cache; the turn's `cache_creation.ephemeral_1h_input_tokens`
    /// is the subset of cache_creation billed at the 1-hour rate (2× input vs 1.25×). The reader
    /// must capture it as `breakdown.cacheWrite1h` so cost prices it correctly.
    func test_claude_captures_one_hour_cache_write_subset() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cw1h-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        // cache_creation_input_tokens = 5199, all of it 1-hour TTL.
        let line = "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"id\":\"msg_X\",\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":16895,\"output_tokens\":603,\"cache_read_input_tokens\":15840,\"cache_creation_input_tokens\":5199,\"cache_creation\":{\"ephemeral_1h_input_tokens\":5199,\"ephemeral_5m_input_tokens\":0}}}}"
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try line.write(to: claudeFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            now: { now }, calendar: cal)

        let claude = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        XCTAssertEqual(claude.breakdown.cacheWrite, 5199)     // total cache creation (unchanged)
        XCTAssertEqual(claude.breakdown.cacheWrite1h, 5199)   // the 1-hour subset, for pricing
        try? fm.removeItem(at: root)
    }

    func test_token_breakdown_split_per_provider_for_cost() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("bd-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)

        // Claude: two turns. Per-type sums: input 100+120=220, output 10+20=30,
        // cacheRead 5+9000=9005, cacheWrite 2+1000=1002. total = 10257.
        let claudeContent = [
            "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}}}",
            "{\"timestamp\":\"2026-06-19T09:05:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":120,\"output_tokens\":20,\"cache_read_input_tokens\":9000,\"cache_creation_input_tokens\":1000}}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try claudeContent.write(to: claudeFile, atomically: true, encoding: .utf8)
        // Reader fast-skips files whose real mtime isn't "today"; stamp it to the injected clock.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        // Codex: input_tokens INCLUDES cached_input_tokens, so the non-cached input is
        // 15586-4992=10594, cacheRead=4992 (the cached subset), output=330, cacheWrite=0.
        let codexContent = [
            "{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab\",\"cwd\":\"/Example/Code/widget\"}}",
            "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":15586,\"cached_input_tokens\":4992,\"output_tokens\":330,\"total_tokens\":15916}}}}",
        ].joined(separator: "\n")
        let codexFile = codexDay.appendingPathComponent("rollout-2026-06-19T08-00-00-019eddab-x.jsonl")
        try codexContent.write(to: codexFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: codexFile.path)

        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)

        let claude = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        XCTAssertEqual(claude.breakdown.input, 220)
        XCTAssertEqual(claude.breakdown.output, 30)
        XCTAssertEqual(claude.breakdown.cacheRead, 9005)
        XCTAssertEqual(claude.breakdown.cacheWrite, 1002)
        XCTAssertEqual(claude.breakdown.total, claude.tokens)   // breakdown is consistent with rolled-up tokens

        let codex = try XCTUnwrap(reader.read().first { $0.provider == .codex })
        XCTAssertEqual(codex.breakdown.input, 10594)
        XCTAssertEqual(codex.breakdown.output, 330)
        XCTAssertEqual(codex.breakdown.cacheRead, 4992)
        XCTAssertEqual(codex.breakdown.cacheWrite, 0)
        XCTAssertEqual(codex.breakdown.total, codex.tokens)

        try? fm.removeItem(at: root)
    }

    func test_claude_context_excludes_sidechains_and_promotes_to_1M_on_overflow() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        // Main turn at 09:05 with 250K occupancy (input+cache). A LATER sub-agent (sidechain)
        // turn at 09:10 must NOT define the main context. Occupancy > 200K ⇒ 1M window.
        let lines = [
            "{\"timestamp\":\"2026-06-19T09:05:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":50000,\"output_tokens\":0,\"cache_read_input_tokens\":190000,\"cache_creation_input_tokens\":10000}}}",
            "{\"timestamp\":\"2026-06-19T09:10:00.000Z\",\"isSidechain\":true,\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_read_input_tokens\":30,\"cache_creation_input_tokens\":0}}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("s.jsonl")
        try lines.write(to: claudeFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            now: { now }, calendar: cal)

        let s = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        XCTAssertEqual(s.contextTokens, 250000)        // main turn only, not the sidechain
        XCTAssertEqual(s.contextWindow, 1_000_000)     // promoted because occupancy > 200K
        XCTAssertEqual(s.contextFraction, 0.25)

        try? fm.removeItem(at: root)
    }

    func test_claude_session_uses_summary_as_title_and_short_id() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("title-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        // A `summary` line carries the conversation title; the usage line carries sessionId.
        let lines = [
            "{\"type\":\"summary\",\"summary\":\"Rename app to Tama\",\"leafUuid\":\"abc\"}",
            "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"sessionId\":\"019eddabcdef1234\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10}}}",
        ].joined(separator: "\n")
        let claudeFile = claudeProj.appendingPathComponent("019eddabcdef1234.jsonl")
        try lines.write(to: claudeFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: claudeFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            now: { now }, calendar: cal)

        let s = try XCTUnwrap(reader.read().first { $0.provider == .claudeCode })
        XCTAssertEqual(s.title, "Rename app to Tama")
        XCTAssertEqual(s.sessionId, "019eddab")          // short, 8 chars
        XCTAssertEqual(s.displayName, "Rename app to Tama")

        try? fm.removeItem(at: root)
    }

    func test_codex_session_uses_first_prompt_as_title_stripping_ide_wrapper() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cxtitle-\(UUID().uuidString)")
        let codexDay = root.appendingPathComponent("codex/2026/06/19")
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)

        // The first user turn is an environment_context block (must be skipped); the real
        // request arrives as a `user_message` wrapped in Codex's IDE-context preamble.
        let lines = [
            "{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddabcafe\",\"cwd\":\"/Users/example/code/widget\"}}",
            "{\"timestamp\":\"2026-06-19T08:00:01.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"<environment_context>\\n  <cwd>/x</cwd>\\n</environment_context>\"}]}}",
            "{\"timestamp\":\"2026-06-19T08:00:02.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"# Context from my IDE setup:\\n## Open tabs:\\n- a.swift\\n\\n## My request for Codex:\\nadd a dark mode toggle to settings\\n\"}}",
            "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"output_tokens\":10,\"total_tokens\":110}}}}",
        ].joined(separator: "\n")
        let codexFile = codexDay.appendingPathComponent("rollout-2026-06-19T08-00-00-019eddabcafe-x.jsonl")
        try lines.write(to: codexFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: codexFile.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("none-c"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)

        let s = try XCTUnwrap(reader.read().first { $0.provider == .codex })
        XCTAssertEqual(s.title, "add a dark mode toggle to settings")   // wrapper stripped, env block skipped
        XCTAssertEqual(s.displayName, "add a dark mode toggle to settings")
        XCTAssertEqual(s.sessionId, "019eddab")

        try? fm.removeItem(at: root)
    }

    /// A Codex rollout is filed under its session-START date, but a long-lived session (e.g. the
    /// VS Code `codex app-server` keeping a thread open across midnight) keeps appending to that
    /// older file. The scan must surface it when it was touched TODAY, and must NOT surface a
    /// session in an old folder that has been idle for days. mtimes are stamped explicitly so this
    /// is independent of the wall clock.
    func test_codex_includes_cross_day_session_touched_today_but_not_stale_ones() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xday-\(UUID().uuidString)")
        // "today" is 06-20; both rollout files live in the 06-18 start-date folder (2 days back).
        let startDay = root.appendingPathComponent("codex/2026/06/18")
        try fm.createDirectory(at: startDay, withIntermediateDirectories: true)

        func codexFile(id: String, cwd: String) -> String {
            [
                "{\"timestamp\":\"2026-06-18T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\"}}",
                "{\"timestamp\":\"2026-06-18T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"output_tokens\":10,\"total_tokens\":110},\"model_context_window\":272000}}}",
            ].joined(separator: "\n")
        }
        let liveFile = startDay.appendingPathComponent("rollout-2026-06-18T08-00-00-019live-x.jsonl")
        let staleFile = startDay.appendingPathComponent("rollout-2026-06-18T08-00-00-019stale-x.jsonl")
        try codexFile(id: "019live00", cwd: "/Example/Code/live").write(to: liveFile, atomically: true, encoding: .utf8)
        try codexFile(id: "019stale0", cwd: "/Example/Code/stale").write(to: staleFile, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-20T12:00:00.000Z")!
        let twoDaysAgo = ISO8601DateFormatter.shared.date(from: "2026-06-18T09:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: liveFile.path)        // touched today
        try fm.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: staleFile.path) // idle since 06-18

        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("none-c"),
            codexSessionsDir: root.appendingPathComponent("codex"),
            now: { now }, calendar: cal)
        let codex = reader.read().filter { $0.provider == .codex }
        XCTAssertEqual(codex.count, 1)                       // only the session active today
        XCTAssertEqual(codex.first?.folder, "/Example/Code/live")
        XCTAssertEqual(codex.first?.contextWindow, 272_000)  // and it parses with full token data

        try? fm.removeItem(at: root)
    }

    /// Token totals are windowed: `.today` counts only this-calendar-day turns, while `.last24h`
    /// counts every turn in the trailing 24h (so it also picks up yesterday-evening work that
    /// `.today` drops at midnight). Claude logs carry per-turn timestamps, so the split is exact.
    func test_claude_tokens_windowed_today_vs_last24h() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("win-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        // now = 06-20T12:00Z. today cutoff = 06-20T00:00Z; 24h cutoff = 06-19T12:00Z.
        //  • 06-19T10:00Z  (26h ago) — outside BOTH windows
        //  • 06-19T18:00Z  (18h ago) — inside 24h, outside today
        //  • 06-20T09:00Z   (3h ago) — inside BOTH
        let lines = [
            "{\"timestamp\":\"2026-06-19T10:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":0}}}",
            "{\"timestamp\":\"2026-06-19T18:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":50}}}",
            "{\"timestamp\":\"2026-06-20T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}",
        ].joined(separator: "\n")
        let file = claudeProj.appendingPathComponent("s.jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-20T12:00:00.000Z")!
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            now: { now }, calendar: cal)

        let today = try XCTUnwrap(reader.scan(window: .today).sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(today.tokens, 15)        // only the 06-20T09:00 turn (10+5)

        let last24h = try XCTUnwrap(reader.scan(window: .last24h).sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(last24h.tokens, 165)     // 06-19T18:00 (100+50) + 06-20T09:00 (10+5)

        try? fm.removeItem(at: root)
    }

    /// The `(mtime, size)` cache stores per-hour buckets, NOT a pre-summed total, so an UNCHANGED
    /// file still windows correctly as the rolling 24h boundary advances between scans. (A cache that
    /// stored the summed total would return the first scan's stale number on the second scan.)
    func test_last24h_total_recomputes_on_unchanged_file_as_clock_advances() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cache24-\(UUID().uuidString)")
        let claudeProj = root.appendingPathComponent("claude/-Users-example-code-myapp")
        try fm.createDirectory(at: claudeProj, withIntermediateDirectories: true)

        let lines = [
            "{\"timestamp\":\"2026-06-20T02:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":0}}}",
            "{\"timestamp\":\"2026-06-20T10:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":10,\"output_tokens\":0}}}",
        ].joined(separator: "\n")
        let file = claudeProj.appendingPathComponent("s.jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)
        let mtime = ISO8601DateFormatter.shared.date(from: "2026-06-20T11:00:00.000Z")!
        try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var clock = ISO8601DateFormatter.shared.date(from: "2026-06-20T12:00:00.000Z")!
        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("claude"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            now: { clock }, calendar: cal)

        // Scan 1 — both turns within the trailing 24h (cutoff 06-19T12:00). Warms the cache.
        let first = try XCTUnwrap(reader.scan(window: .last24h).sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(first.tokens, 110)

        // Advance 15h without touching the file. Cutoff moves to 06-20T03:00, ageing out the 02:00 turn.
        clock = ISO8601DateFormatter.shared.date(from: "2026-06-21T03:00:00.000Z")!
        let second = try XCTUnwrap(reader.scan(window: .last24h).sessions.first { $0.provider == .claudeCode })
        XCTAssertEqual(second.tokens, 10)   // only the 06-20T10:00 turn remains in the window

        try? fm.removeItem(at: root)
    }

    func test_lists_gemini_and_antigravity_by_folder_no_token_data() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ga-\(UUID().uuidString)")
        let geminiTmp = root.appendingPathComponent("gemini-tmp")
        let gProj = geminiTmp.appendingPathComponent("gem-app")
        try fm.createDirectory(at: gProj, withIntermediateDirectories: true)

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!

        // Gemini: .project_root holds the real folder; logs.json mtime is the recency signal.
        try "/Example/Code/gem-app\n".write(to: gProj.appendingPathComponent(".project_root"), atomically: true, encoding: .utf8)
        let gLog = gProj.appendingPathComponent("logs.json")
        try "[]".write(to: gLog, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: gLog.path)

        // Antigravity: history.jsonl lines carry workspace + ms timestamp.
        let antiFile = root.appendingPathComponent("history.jsonl")
        let ms = now.timeIntervalSince1970 * 1000
        try "{\"display\":\"hi\",\"workspace\":\"/Example/Code/ag-app\",\"timestamp\":\(ms)}"
            .write(to: antiFile, atomically: true, encoding: .utf8)

        let reader = ActiveSessionsReader(
            claudeProjectsDir: root.appendingPathComponent("none-c"),
            codexSessionsDir: root.appendingPathComponent("none-x"),
            geminiTmpDir: geminiTmp, antigravityHistoryFile: antiFile,
            now: { now }, calendar: cal)
        let sessions = reader.read()

        let gem = try XCTUnwrap(sessions.first { $0.provider == .gemini })
        XCTAssertEqual(gem.project, "gem-app")
        XCTAssertEqual(gem.folder, "/Example/Code/gem-app")
        XCTAssertEqual(gem.tokens, 0)
        XCTAssertNil(gem.model)

        let ag = try XCTUnwrap(sessions.first { $0.provider == .antigravity })
        XCTAssertEqual(ag.project, "ag-app")
        XCTAssertEqual(ag.folder, "/Example/Code/ag-app")
        XCTAssertEqual(ag.tokens, 0)

        try? fm.removeItem(at: root)
    }
}

final class ActiveSessionsReaderAccountsTests: XCTestCase {
    func test_sessions_from_extra_roots_are_tagged_with_their_account_label_and_totals_include_them() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("accounts-\(UUID().uuidString)")
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func claudeLog(_ home: String, tokens: Int) throws {
            let proj = root.appendingPathComponent("\(home)/projects/-Example-Code-myapp")
            try fm.createDirectory(at: proj, withIntermediateDirectories: true)
            let f = proj.appendingPathComponent("s.jsonl")
            try "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"usage\":{\"input_tokens\":\(tokens),\"output_tokens\":0}}}"
                .write(to: f, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path)
        }
        try claudeLog("home/.claude", tokens: 100)
        try claudeLog("home/.claude-work", tokens: 1000)
        let codexDay = root.appendingPathComponent("home/codex-b/sessions/2026/06/19")
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)
        let cx = codexDay.appendingPathComponent("rollout-2026-06-19T08-00-00-019eddab-x.jsonl")
        try ["{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab\",\"cwd\":\"/Example/Code/widget\"}}",
             "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":50,\"cached_input_tokens\":0,\"output_tokens\":5,\"total_tokens\":55}}}}"]
            .joined(separator: "\n").write(to: cx, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: cx.path)

        let roots = [
            AccountRoot(provider: .claudeCode, label: nil, root: root.appendingPathComponent("home/.claude")),
            AccountRoot(provider: .claudeCode, label: "work", root: root.appendingPathComponent("home/.claude-work")),
            AccountRoot(provider: .codex, label: "B", root: root.appendingPathComponent("home/codex-b")),
        ]
        let reader = ActiveSessionsReader(roots: { roots }, now: { now }, calendar: cal)
        let activity = reader.scan()
        let claude = activity.sessions.filter { $0.provider == .claudeCode }.sorted { $0.tokens < $1.tokens }
        XCTAssertEqual(claude.map { $0.account }, [nil, "work"])
        XCTAssertEqual(activity.totals[.claudeCode], 1100, "provider total spans every account")
        let codex = try XCTUnwrap(activity.sessions.first { $0.provider == .codex })
        XCTAssertEqual(codex.account, "B")
        XCTAssertNotEqual(claude[0].id, claude[1].id, "same folder in two accounts must not collide")
        try? fm.removeItem(at: root)
    }

    func test_roots_closure_is_consulted_on_every_scan() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("accounts-\(UUID().uuidString)")
        let now = ISO8601DateFormatter.shared.date(from: "2026-06-19T12:00:00.000Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let proj = root.appendingPathComponent("x/projects/-p")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)
        let f = proj.appendingPathComponent("s.jsonl")
        try "{\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}"
            .write(to: f, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path)
        nonisolated(unsafe) var roots: [AccountRoot] = []
        let reader = ActiveSessionsReader(roots: { roots }, now: { now }, calendar: cal)
        XCTAssertTrue(reader.scan().sessions.isEmpty)
        roots = [AccountRoot(provider: .claudeCode, label: "x", root: root.appendingPathComponent("x"))]
        XCTAssertEqual(reader.scan().sessions.count, 1, "a root added in Settings shows up without restarting")
        try? fm.removeItem(at: root)
    }
}
