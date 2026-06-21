import Foundation

/// Something that can produce an `Activity` snapshot (the reader, or a test mock).
public protocol ActivityScanning: Sendable {
    func scan() -> Activity
    /// Scan with token/cost totals restricted to the given window. Defaults to `.today`.
    func scan(window: TokenWindow) -> Activity
}

public extension ActivityScanning {
    /// Default for conformers (e.g. test mocks) that don't window: ignore the window.
    func scan(window: TokenWindow) -> Activity { scan() }
}

/// Result of one scan: the (capped) session list for display + full per-provider token totals,
/// with the per-type breakdown needed to price each provider's usage.
public struct Activity: Sendable, Equatable {
    public let sessions: [SessionInfo]
    public let totals: [Provider: Int]
    public let breakdowns: [Provider: TokenBreakdown]
    /// Per-provider tokens split by model id (the session's `model`, or "" if unknown). The basis
    /// for accurate cost: Claude prices each model tier differently, so the provider total must be
    /// summed per model rather than priced as one flat aggregate.
    public let modelBreakdowns: [Provider: [String: TokenBreakdown]]
    public init(sessions: [SessionInfo], totals: [Provider: Int],
                breakdowns: [Provider: TokenBreakdown] = [:],
                modelBreakdowns: [Provider: [String: TokenBreakdown]] = [:]) {
        self.sessions = sessions
        self.totals = totals
        self.breakdowns = breakdowns
        self.modelBreakdowns = modelBreakdowns
    }
    /// Build from per-provider breakdowns; the integer totals are derived from them.
    public init(sessions: [SessionInfo], breakdowns: [Provider: TokenBreakdown]) {
        self.init(sessions: sessions, totals: breakdowns.mapValues { $0.total }, breakdowns: breakdowns)
    }
    /// Build from per-provider, per-model breakdowns; rolled-up breakdowns and totals are derived.
    public init(sessions: [SessionInfo], modelBreakdowns: [Provider: [String: TokenBreakdown]]) {
        let rolled = modelBreakdowns.mapValues { $0.values.reduce(TokenBreakdown(), +) }
        self.init(sessions: sessions, totals: rolled.mapValues { $0.total },
                  breakdowns: rolled, modelBreakdowns: modelBreakdowns)
    }
    public static let empty = Activity(sessions: [], totals: [:])
}

/// Reads recently-active agent sessions (project + folder + today's tokens + model) and
/// per-provider token totals from the agents' local logs. Strictly read-only.
///
/// Performance: parsing is cached per file by (mtime, size). The vast majority of today's
/// log files never change between scans, so they are parsed once; only the file(s) being
/// actively written are re-read. This keeps a scan cheap even with tens of MB of logs.
public final class ActiveSessionsReader: ActivityScanning, @unchecked Sendable {
    private let claudeProjectsDir: URL
    private let codexSessionsDir: URL
    private let geminiTmpDir: URL?
    private let antigravityHistoryFile: URL?
    private let now: () -> Date
    private let calendar: Calendar
    private let limit: Int

    /// One file's parsed contribution = one session.
    ///
    /// Token usage is stored per-hour (`buckets`, keyed by hours-since-epoch) rather than
    /// pre-summed, so a single parse serves any time window: a scan sums the buckets at or after
    /// the window's cutoff hour. The buckets depend only on file content, so they stay valid in the
    /// `(mtime, size)` cache even as the rolling 24h boundary moves between scans. Claude logs carry
    /// per-turn timestamps (one bucket per turn's hour); Codex is session-cumulative, so its whole
    /// breakdown lands in a single bucket at the session's last-activity hour.
    private struct Entry {
        let mtime: Date
        let size: Int
        let provider: Provider
        let folder: String
        let buckets: [Int: TokenBreakdown]   // hours-since-epoch → that hour's token breakdown
        let contextTokens: Int     // live context-window occupancy (last turn input side)
        let contextWindow: Int     // model max context window; 0 if unknown
        let last: Date
        let model: String?
        let session: String?
        let title: String?
        let messages: Int          // conversation length (user+assistant turns)
    }

    /// Hour bucket key for a timestamp (hours since the Unix epoch).
    private static func hourKey(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }

    /// Lowest bucket key still inside the window, given the scan's clock.
    private func cutoffHour(_ window: TokenWindow, now: Date) -> Int {
        switch window {
        case .today:   return Self.hourKey(calendar.startOfDay(for: now))
        case .last24h: return Self.hourKey(now.addingTimeInterval(-24 * 3600))
        }
    }

    /// Whether a file touched at `mtime` falls in the window (used to pre-filter the directory walk).
    private func inWindow(_ mtime: Date, _ window: TokenWindow, now: Date) -> Bool {
        switch window {
        case .today:   return calendar.isDate(mtime, inSameDayAs: now)
        case .last24h: return mtime >= now.addingTimeInterval(-24 * 3600)
        }
    }
    private var cache: [String: Entry] = [:]

    public init(claudeProjectsDir: URL, codexSessionsDir: URL,
                geminiTmpDir: URL? = nil, antigravityHistoryFile: URL? = nil,
                now: @escaping () -> Date, calendar: Calendar = .current, limit: Int = 16) {
        self.claudeProjectsDir = claudeProjectsDir
        self.codexSessionsDir = codexSessionsDir
        self.geminiTmpDir = geminiTmpDir
        self.antigravityHistoryFile = antigravityHistoryFile
        self.now = now
        self.calendar = calendar
        self.limit = limit
    }

    public convenience init(now: @escaping () -> Date, calendar: Calendar = .current, limit: Int = 16) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(claudeProjectsDir: home.appendingPathComponent(".claude/projects"),
                  codexSessionsDir: home.appendingPathComponent(".codex/sessions"),
                  geminiTmpDir: home.appendingPathComponent(".gemini/tmp"),
                  antigravityHistoryFile: home.appendingPathComponent(".gemini/antigravity-cli/history.jsonl"),
                  now: now, calendar: calendar, limit: limit)
    }

    /// Backwards-compatible accessor returning just the session list (today's window).
    public func read() -> [SessionInfo] { scan().sessions }

    public func scan() -> Activity { scan(window: .today) }

    /// One cached pass over all providers' logs, with token/cost totals restricted to `window`.
    public func scan(window: TokenWindow) -> Activity {
        let today = now()
        var entries: [Entry] = []
        var fresh: [String: Entry] = [:]
        entries.reserveCapacity(limit * 2)
        fresh.reserveCapacity(cache.count)

        scanClaude(window: window, now: today, into: &entries, fresh: &fresh)
        scanCodex(window: window, now: today, into: &entries, fresh: &fresh)
        cache = fresh                                   // drop entries for files no longer in window
        entries += geminiSessions(window: window, now: today)      // small/cheap, not cached
        entries += antigravitySessions(window: window, now: today) // single small file, not cached

        // One session per entry (no folder merge). Each entry's token breakdown for THIS window is
        // the sum of its hour-buckets at/after the cutoff; provider totals sum those windowed breakdowns.
        let cutoff = cutoffHour(window, now: today)
        func windowed(_ e: Entry) -> TokenBreakdown {
            e.buckets.reduce(TokenBreakdown()) { $1.key >= cutoff ? $0 + $1.value : $0 }
        }
        var breakdowns: [Provider: TokenBreakdown] = [:]
        var modelBreakdowns: [Provider: [String: TokenBreakdown]] = [:]
        let sessions = entries
            .map { e -> SessionInfo in
                let bd = windowed(e)
                breakdowns[e.provider, default: TokenBreakdown()] = breakdowns[e.provider, default: TokenBreakdown()] + bd
                let modelKey = e.model ?? ""   // "" = unknown model → priced at the provider default
                modelBreakdowns[e.provider, default: [:]][modelKey, default: TokenBreakdown()] =
                    modelBreakdowns[e.provider, default: [:]][modelKey, default: TokenBreakdown()] + bd
                return SessionInfo(provider: e.provider, project: URL(fileURLWithPath: e.folder).lastPathComponent,
                            folder: e.folder, lastActivity: e.last, tokens: bd.total,
                            cacheTokens: bd.cacheRead + bd.cacheWrite, contextTokens: e.contextTokens,
                            contextWindow: e.contextWindow, model: e.model, sessionId: e.session,
                            title: e.title, breakdown: bd, messages: e.messages)
            }
            .sorted { $0.lastActivity > $1.lastActivity }
        return Activity(sessions: Array(sessions.prefix(limit)),
                        totals: breakdowns.mapValues { $0.total },
                        breakdowns: breakdowns, modelBreakdowns: modelBreakdowns)
    }

    // MARK: Cached file parsing

    /// Returns the cached entry if (mtime, size) match, else parses via `parse` and caches it.
    private func cached(_ file: URL, fresh: inout [String: Entry], parse: (URL) -> Entry?) -> Entry? {
        guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = vals.contentModificationDate, let size = vals.fileSize else { return nil }
        let key = file.path
        if let hit = cache[key], hit.mtime == mtime, hit.size == size {
            fresh[key] = hit
            return hit
        }
        guard let parsed = parse(file) else { return nil }
        let entry = Entry(mtime: mtime, size: size, provider: parsed.provider, folder: parsed.folder,
                          buckets: parsed.buckets, contextTokens: parsed.contextTokens, contextWindow: parsed.contextWindow,
                          last: parsed.last, model: parsed.model, session: parsed.session, title: parsed.title,
                          messages: parsed.messages)
        fresh[key] = entry
        return entry
    }

    private func scanClaude(window: TokenWindow, now: Date, into entries: inout [Entry], fresh: inout [String: Entry]) {
        let fm = FileManager.default
        let directoryKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let fileKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let dirs = try? fm.contentsOfDirectory(at: claudeProjectsDir, includingPropertiesForKeys: directoryKeys) else { return }
        for dir in dirs {
            guard SafeFileReader.isSafeDirectory(dir) else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: fileKeys) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let mod = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      inWindow(mod, window, now: now) else { continue }
                if let e = cached(file, fresh: &fresh, parse: { self.parseClaude($0) }) { entries.append(e) }
            }
        }
    }

    private func parseClaude(_ file: URL) -> Entry? {
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
        return Entry(mtime: .distantPast, size: 0, provider: .claudeCode, folder: f,
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

    /// How many day-folders back to scan for Codex rollouts. Codex files each rollout under its
    /// session-START date, but a long-lived session (e.g. the VS Code `codex app-server` keeping a
    /// thread open across midnight) keeps appending to that same older file. So we look back a few
    /// days and keep any file whose mtime is today — matching the Claude scan, which filters by file
    /// mtime rather than a date-named folder. Cheap: unchanged files are cache hits.
    private let codexLookbackDays = 14

    private func scanCodex(window: TokenWindow, now: Date, into entries: inout [Entry], fresh: inout [String: Entry]) {
        let fm = FileManager.default
        let fileKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        for dayOffset in 0..<codexLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let dayDir = codexSessionsDir.appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", m)).appendingPathComponent(String(format: "%02d", d))
            guard SafeFileReader.isSafeDirectory(dayDir) else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: fileKeys) else { continue }
            for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                // Only sessions touched in-window (older folders may hold sessions last active days ago).
                guard let mod = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      inWindow(mod, window, now: now) else { continue }
                if let e = cached(file, fresh: &fresh, parse: { self.parseCodex($0) }) { entries.append(e) }
            }
        }
    }

    private func parseCodex(_ file: URL) -> Entry? {
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
        return Entry(mtime: .distantPast, size: 0, provider: .codex, folder: folder,
                     buckets: buckets, contextTokens: contextTokens, contextWindow: contextWindow,
                     last: mtime, model: model, session: session, title: firstPrompt, messages: messages)
    }

    // MARK: Gemini / Antigravity (small, read each scan)

    private func geminiSessions(window: TokenWindow, now: Date) -> [Entry] {
        guard let geminiTmpDir, let dirs = try? FileManager.default.contentsOfDirectory(at: geminiTmpDir, includingPropertiesForKeys: nil) else { return [] }
        var out: [Entry] = []
        for dir in dirs {
            guard SafeFileReader.isSafeDirectory(dir),
                  let folderData = SafeFileReader.data(at: dir.appendingPathComponent(".project_root"), maxBytes: SafeFileReader.maxMetadataBytes) else { continue }
            let folder = String(decoding: folderData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folder.isEmpty else { continue }
            let logFile = dir.appendingPathComponent("logs.json")
            let last = (try? logFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let last, inWindow(last, window, now: now) else { continue }
            out.append(Entry(mtime: .distantPast, size: 0, provider: .gemini, folder: folder,
                             buckets: [:], contextTokens: 0, contextWindow: 0,
                             last: last, model: nil, session: nil, title: nil, messages: 0))
        }
        return out
    }

    private func antigravitySessions(window: TokenWindow, now: Date) -> [Entry] {
        guard let antigravityHistoryFile,
              let data = SafeFileReader.data(at: antigravityHistoryFile, maxBytes: SafeFileReader.maxHistoryBytes) else { return [] }
        var byFolder: [String: Date] = [:]
        SafeFileReader.forEachLineData(in: data) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ws = obj["workspace"] as? String, !ws.isEmpty, let ms = obj["timestamp"] as? Double else { return }
            let date = Date(timeIntervalSince1970: ms / 1000)
            if let e = byFolder[ws], e >= date { return }
            byFolder[ws] = date
        }
        return byFolder.compactMap { folder, date in
            inWindow(date, window, now: now)
                ? Entry(mtime: .distantPast, size: 0, provider: .antigravity, folder: folder,
                        buckets: [:], contextTokens: 0, contextWindow: 0,
                        last: date, model: nil, session: nil, title: nil, messages: 0)
                : nil
        }
    }
}
