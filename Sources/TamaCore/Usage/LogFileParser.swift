import Foundation

/// One file's parsed contribution = one session, before the reader's cache wraps it with
/// (mtime, size). Shared by `ActiveSessionsReader` today and `HistoryReader` in future.
///
/// Token usage is stored per-hour (`buckets`, keyed by hours-since-epoch) rather than
/// pre-summed, so a single parse serves any time window: a scan sums the buckets at or after
/// the window's cutoff hour. The buckets depend only on file content, so they stay valid in the
/// `(mtime, size)` cache even as the rolling 24h boundary moves between scans. Claude logs carry
/// per-turn timestamps (one bucket per turn's hour); Codex is session-cumulative, so its whole
/// breakdown lands in a single bucket at the session's last-activity hour.
struct ParsedLog {
    let provider: Provider
    let folder: String
    let buckets: [Int: TokenBreakdown]   // hours-since-epoch → that hour's tokens
    let contextTokens: Int
    let contextWindow: Int
    let last: Date
    let model: String?
    let session: String?
    let title: String?
    let messages: Int
}

/// Parses Claude Code / Codex session log lines into `ParsedLog`. Pure, stateless, no I/O beyond
/// `SafeFileReader`'s read-only line iteration — safe to share across readers.
enum LogFileParser {
    /// Hour bucket key for a timestamp (hours since the Unix epoch).
    static func hourKey(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }

    static func parseClaude(_ file: URL) -> ParsedLog? {
        var folder: String?, buckets: [Int: TokenBreakdown] = [:], last = Date.distantPast, model: String?, session: String?, title: String?, firstPrompt: String?, messages = 0
        // Context-window occupancy = the most recent MAIN-thread assistant turn's input side plus
        // its output (sub-agent sidechains have their own separate context, so they don't count).
        var ctxLast = Date.distantPast, contextTokens = 0
        // Claude Code (v2.x) writes ONE assistant reply as several jsonl lines — one per content
        // block (thinking, text, each tool_use) — and repeats the SAME message-level `usage` on
        // every line. Counting each line double-counts tokens (~2x, more on multi-block turns), so
        // we tally a reply's usage and message ONCE per `message.id` (every id-bearing assistant
        // line carries the usage, so the first sighting is enough). This matches `claude /cost`.
        var seenMsgIds = Set<String>()
        SafeFileReader.forEachLineData(at: file) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            // `summary` lines carry the conversation title (what `claude --resume` shows).
            if (obj["type"] as? String) == "summary", let s = obj["summary"] as? String, !s.isEmpty { title = s }
            let type = obj["type"] as? String
            let messageObj = obj["message"] as? [String: Any]
            if type == "assistant", let id = messageObj?["id"] as? String {
                if seenMsgIds.contains(id) { return }   // a later split line of an already-counted reply
                seenMsgIds.insert(id)
            }
            // Conversation length = each real user prompt + each distinct assistant reply (the number
            // `/resume` shows). `isMeta` user lines are injected metadata (e.g. an image-cache
            // reference), not messages; split assistant lines are deduped by id above.
            if type == "user", (obj["isMeta"] as? Bool) != true { messages += 1 }
            else if type == "assistant" { messages += 1 }
            // Fallback name: the first real user prompt (what started the conversation).
            if firstPrompt == nil, type == "user", (obj["isMeta"] as? Bool) != true,
               let m = messageObj, let p = Self.userPrompt(m) { firstPrompt = p }
            guard let ts = obj["timestamp"] as? String,
                  let date = ISO8601DateFormatter.shared.date(from: ts),
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty,
                  let message = messageObj,
                  let usage = message["usage"] as? [String: Any] else { return }
            folder = cwd
            if session == nil, let sid = obj["sessionId"] as? String { session = String(sid.prefix(8)) }
            let input = usage["input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
            // 1-hour cache-write subset (billed 2× input vs 1.25×). Claude Code writes 1-hour cache.
            let cacheWrite1h = (usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? Int ?? 0
            let key = Self.hourKey(date)   // bucket every turn by its hour; scan sums per window
            buckets[key, default: TokenBreakdown()] = buckets[key, default: TokenBreakdown()]
                + TokenBreakdown(input: input, output: usage["output_tokens"] as? Int ?? 0,
                                 cacheRead: cacheRead, cacheWrite: cacheWrite, cacheWrite1h: cacheWrite1h)
            if date >= last { last = date; if let m = message["model"] as? String, !m.isEmpty { model = m } }
            // Live context occupancy from the latest non-sidechain turn: input + cache + this turn's output.
            if (obj["isSidechain"] as? Bool) != true, date >= ctxLast {
                ctxLast = date; contextTokens = input + cacheRead + cacheWrite + (usage["output_tokens"] as? Int ?? 0)
            }
        }
        guard let f = folder else { return nil }
        let sid = session ?? String(file.deletingPathExtension().lastPathComponent.prefix(8))
        return ParsedLog(provider: .claudeCode, folder: f,
                     buckets: buckets, contextTokens: contextTokens,
                     contextWindow: Self.claudeContextWindow(model: model, occupancy: contextTokens),
                     last: last, model: model, session: sid, title: title ?? firstPrompt, messages: messages)
    }

    /// Claude logs don't carry the context-window size, so infer it. Default 200K; the only way
    /// occupancy can exceed 200K is a 1M-context (beta) session, so promote on overflow.
    static func claudeContextWindow(model: String?, occupancy: Int) -> Int {
        let m = model?.lowercased() ?? ""
        if m.contains("[1m]") || m.contains("-1m") || occupancy > 200_000 { return 1_000_000 }
        return 200_000
    }

    /// Extract a human prompt from a Claude `user` message, or nil if it isn't a real
    /// prompt (tool result, slash-command/system block, or empty). Trimmed + capped.
    static func userPrompt(_ message: [String: Any]) -> String? {
        var raw: String?
        if let s = message["content"] as? String {
            raw = s
        } else if let arr = message["content"] as? [[String: Any]] {
            if arr.contains(where: { ($0["type"] as? String) == "tool_result" }) { return nil }
            let texts = arr.compactMap { ($0["type"] as? String) == "text" ? ($0["text"] as? String) : nil }
            raw = texts.joined(separator: " ")
        }
        return cleanPrompt(raw)
    }

    /// Extract the opening human prompt from a Codex `user_message` / `message` text, stripping
    /// the IDE-context wrapper Codex prepends ("…## My request for Codex:\n<actual request>").
    static func codexPrompt(_ raw: String) -> String? {
        var t = raw
        if let r = t.range(of: "## My request for Codex:") { t = String(t[r.upperBound...]) }
        return cleanPrompt(t)
    }

    /// Shared: trim, drop system/tag/interrupted blocks, collapse whitespace, cap at 80 chars.
    private static func cleanPrompt(_ raw: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("<") || t.hasPrefix("[Request interrupted") { return nil }
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return t.count > 80 ? String(t.prefix(80)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    static func parseCodex(_ file: URL) -> ParsedLog? {
        var cwd: String?, lastInput = 0, lastOutput = 0, lastCache = 0, contextTokens = 0, contextWindow = 0, model: String?, session: String?, firstPrompt: String?, messages = 0
        SafeFileReader.forEachLineData(at: file) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            let payload = obj["payload"] as? [String: Any]
            if (obj["type"] as? String) == "session_meta" {
                if cwd == nil, let c = payload?["cwd"] as? String, !c.isEmpty { cwd = c }
                if session == nil, let sid = payload?["id"] as? String { session = String(sid.prefix(8)) }
            }
            if (obj["type"] as? String) == "turn_context", let mm = payload?["model"] as? String, !mm.isEmpty { model = mm }
            // Conversation length = transcript `message` items with role user/assistant (the
            // duplicated user_message/agent_message events and developer/system roles don't count).
            if (payload?["type"] as? String) == "message", let role = payload?["role"] as? String,
               role == "user" || role == "assistant" { messages += 1 }
            // Conversation name: the first real user prompt. Codex stores it as a `user_message`
            // event, or as a `message` response_item with role=user (an `input_text` block).
            if firstPrompt == nil {
                if (payload?["type"] as? String) == "user_message", let msg = payload?["message"] as? String {
                    firstPrompt = Self.codexPrompt(msg)
                } else if (payload?["type"] as? String) == "message", (payload?["role"] as? String) == "user",
                          let content = payload?["content"] as? [[String: Any]] {
                    let texts = content.compactMap { ($0["type"] as? String) == "input_text" ? ($0["text"] as? String) : nil }
                    if !texts.isEmpty { firstPrompt = Self.codexPrompt(texts.joined(separator: " ")) }
                }
            }
            if (payload?["type"] as? String) == "token_count", let info = payload?["info"] as? [String: Any] {
                if let total = info["total_token_usage"] as? [String: Any] {
                    lastInput = total["input_tokens"] as? Int ?? 0     // includes the cached subset
                    lastOutput = total["output_tokens"] as? Int ?? 0
                    lastCache = total["cached_input_tokens"] as? Int ?? 0
                }
                // Context occupancy = last turn's input side (already includes cached_input_tokens)
                // plus that turn's output, to match the window's fill after the last response.
                if let lastTurn = info["last_token_usage"] as? [String: Any] {
                    contextTokens = (lastTurn["input_tokens"] as? Int ?? 0) + (lastTurn["output_tokens"] as? Int ?? 0)
                }
                if let w = info["model_context_window"] as? Int, w > 0 { contextWindow = w }
            }
        }
        guard let folder = cwd else { return nil }
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        // `input_tokens` includes `cached_input_tokens`; split the cached part out for pricing.
        let breakdown = TokenBreakdown(input: max(0, lastInput - lastCache), output: lastOutput,
                                       cacheRead: lastCache, cacheWrite: 0)
        // Codex reports a session-cumulative total (not per-turn), so the whole breakdown lands in a
        // single bucket at the session's last-activity hour. The window then includes it all-or-nothing,
        // matching its recency-gated semantics (the file is only scanned when touched within the window).
        let buckets = breakdown.total > 0 ? [Self.hourKey(mtime): breakdown] : [:]
        return ParsedLog(provider: .codex, folder: folder,
                     buckets: buckets, contextTokens: contextTokens, contextWindow: contextWindow,
                     last: mtime, model: model, session: session, title: firstPrompt, messages: messages)
    }
}
