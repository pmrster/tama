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

    /// Lowest bucket key still inside the window, given the scan's clock.
    private func cutoffHour(_ window: TokenWindow, now: Date) -> Int {
        switch window {
        case .today:   return LogFileParser.hourKey(calendar.startOfDay(for: now))
        case .last24h: return LogFileParser.hourKey(now.addingTimeInterval(-24 * 3600))
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

    /// Adapt a ParsedLog to the reader's cache Entry (mtime/size are filled in by `cached`).
    private static func entry(from p: ParsedLog?) -> Entry? {
        guard let p else { return nil }
        return Entry(mtime: .distantPast, size: 0, provider: p.provider, folder: p.folder,
                     buckets: p.buckets, contextTokens: p.contextTokens, contextWindow: p.contextWindow,
                     last: p.last, model: p.model, session: p.session, title: p.title, messages: p.messages)
    }

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
                if let e = cached(file, fresh: &fresh, parse: { Self.entry(from: LogFileParser.parseClaude($0)) }) { entries.append(e) }
            }
        }
    }

    // Forwarders kept for existing callers/tests; the logic lives in LogFileParser.
    static func claudeContextWindow(model: String?, occupancy: Int) -> Int {
        LogFileParser.claudeContextWindow(model: model, occupancy: occupancy)
    }
    static func userPrompt(_ message: [String: Any]) -> String? { LogFileParser.userPrompt(message) }
    static func codexPrompt(_ raw: String) -> String? { LogFileParser.codexPrompt(raw) }

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
                if let e = cached(file, fresh: &fresh, parse: { Self.entry(from: LogFileParser.parseCodex($0)) }) { entries.append(e) }
            }
        }
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
