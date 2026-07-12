import Foundation

/// One history scan's output: per-day rollups plus a Claude-only weekday×hour token grid.
/// `weekdayHour` is ALWAYS 168 entries — index (weekday-1)*24 + hour, Calendar weekday
/// 1=Sunday…7=Saturday — zero-filled, so consumers index without bounds checks.
public struct UsageScan: Sendable, Equatable {
    public let days: [DayUsage]
    public let weekdayHour: [Int]
    public init(days: [DayUsage], weekdayHour: [Int]) {
        self.days = days
        if weekdayHour.count == 168 { self.weekdayHour = weekdayHour }
        else if weekdayHour.count > 168 { self.weekdayHour = Array(weekdayHour.prefix(168)) }
        else { self.weekdayHour = weekdayHour + Array(repeating: 0, count: 168 - weekdayHour.count) }
    }
    /// No per-day usage found (the grid is zero-filled whenever `days` is empty). Kept so
    /// existing `scanHistory(...).isEmpty` call sites (e.g. safety tests) read naturally.
    public var isEmpty: Bool { days.isEmpty }
}

/// Something that can produce a per-day usage history (the reader, or a test mock).
public protocol HistoryScanning: Sendable {
    func scanHistory(days: Int) -> UsageScan
}

/// Read-only back-scan of Claude/Codex logs into per-day usage, for the Today/7d/30d view.
/// Deliberately SEPARATE from the hot 7s `ActiveSessionsReader` path: this one touches up to
/// 30 days of files but runs rarely (launch / hourly / day rollover), off the main thread.
/// Shares the per-line parsers via `LogFileParser`; caches per file by (mtime, size) so old,
/// never-changing files parse at most once per launch. Strictly read-only.
public final class HistoryReader: HistoryScanning, @unchecked Sendable {
    private let claudeProjectsDir: URL
    private let codexSessionsDir: URL
    private let now: () -> Date
    private let calendar: Calendar

    /// One file's cached contribution: its tokens split per local day.
    private struct Contribution {
        let mtime: Date
        let size: Int
        let provider: Provider
        let project: String                    // folder basename — display only
        let model: String                      // "" = unknown → provider default pricing
        let byDay: [String: TokenBreakdown]    // day key → tokens
        // day key → ((weekday-1)*24+hour → tokens); empty for Codex. Keyed by day so the
        // aggregate can window-clamp it exactly like `byDay` — a file touched inside the window
        // may still contain turns from older days (a long-lived / resumed session), and those
        // must NOT leak into the "last 30 days" heatmap.
        let hourlyByDay: [String: [Int: Int]]
    }
    private var cache: [String: Contribution] = [:]

    public init(claudeProjectsDir: URL, codexSessionsDir: URL,
                now: @escaping () -> Date, calendar: Calendar = .current) {
        self.claudeProjectsDir = claudeProjectsDir
        self.codexSessionsDir = codexSessionsDir
        self.now = now
        self.calendar = calendar
    }

    public convenience init(now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(claudeProjectsDir: home.appendingPathComponent(".claude/projects"),
                  codexSessionsDir: home.appendingPathComponent(".codex/sessions"),
                  now: now, calendar: calendar)
    }

    public func scanHistory(days: Int) -> UsageScan {
        let today = now()
        let startOfToday = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        let startKey = UsageHistory.dayKey(windowStart, calendar: calendar)
        let todayKey = UsageHistory.dayKey(today, calendar: calendar)

        var contributions: [Contribution] = []
        var fresh: [String: Contribution] = [:]
        scanClaude(since: windowStart, into: &contributions, fresh: &fresh)
        scanCodex(days: days, now: today, into: &contributions, fresh: &fresh)
        cache = fresh   // drop entries for files no longer in the window

        // Aggregate per day, clamped to [startKey, todayKey] (drops buckets older than the
        // window inside still-recent files, and future-dated lines).
        var byDay: [String: DayUsage] = [:]
        var grid = Array(repeating: 0, count: 168)
        for c in contributions {
            for (day, bd) in c.byDay where day >= startKey && day <= todayKey {
                var d = byDay[day] ?? DayUsage(day: day)
                d.models[c.provider, default: [:]][c.model] = (d.models[c.provider]?[c.model] ?? TokenBreakdown()) + bd
                d.projects[c.provider, default: [:]][c.project] = (d.projects[c.provider]?[c.project] ?? TokenBreakdown()) + bd
                byDay[day] = d
            }
            // Same [startKey, todayKey] clamp as byDay, so out-of-window turns inside a
            // recently-touched file don't inflate the heatmap.
            for (day, cells) in c.hourlyByDay where day >= startKey && day <= todayKey {
                for (cell, tok) in cells where cell >= 0 && cell < 168 { grid[cell] += tok }
            }
        }
        return UsageScan(days: byDay.values.sorted { $0.day < $1.day }, weekdayHour: grid)
    }

    // MARK: Cached file parsing (same (mtime, size) pattern as ActiveSessionsReader)

    private func cached(_ file: URL, fresh: inout [String: Contribution],
                        parse: (URL) -> Contribution?) -> Contribution? {
        guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = vals.contentModificationDate, let size = vals.fileSize else { return nil }
        let key = file.path
        if let hit = cache[key], hit.mtime == mtime, hit.size == size {
            fresh[key] = hit
            return hit
        }
        guard let parsed = parse(file) else { return nil }
        let entry = Contribution(mtime: mtime, size: size, provider: parsed.provider,
                                 project: parsed.project, model: parsed.model,
                                 byDay: parsed.byDay, hourlyByDay: parsed.hourlyByDay)
        fresh[key] = entry
        return entry
    }

    private func scanClaude(since windowStart: Date, into contributions: inout [Contribution],
                            fresh: inout [String: Contribution]) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: claudeProjectsDir,
                                                     includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for dir in dirs {
            guard SafeFileReader.isSafeDirectory(dir) else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dir,
                                                          includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let mod = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      mod >= windowStart else { continue }
                if let c = cached(file, fresh: &fresh, parse: { self.claudeContribution($0) }) {
                    contributions.append(c)
                }
            }
        }
    }

    /// Claude: bucket each turn's usage by the turn's OWN timestamp (files span days).
    private func claudeContribution(_ file: URL) -> Contribution? {
        guard let p = LogFileParser.parseClaude(file) else { return nil }
        var byDay: [String: TokenBreakdown] = [:]
        var hourlyByDay: [String: [Int: Int]] = [:]
        for (hour, bd) in p.buckets {
            let date = Date(timeIntervalSince1970: TimeInterval(hour) * 3600)
            let day = UsageHistory.dayKey(date, calendar: calendar)
            byDay[day, default: TokenBreakdown()] = (byDay[day] ?? TokenBreakdown()) + bd
            let comps = calendar.dateComponents([.weekday, .hour], from: date)
            if let w = comps.weekday, let h = comps.hour {
                hourlyByDay[day, default: [:]][(w - 1) * 24 + h, default: 0] += bd.total
            }
        }
        return Contribution(mtime: .distantPast, size: 0, provider: .claudeCode,
                            project: URL(fileURLWithPath: p.folder).lastPathComponent,
                            model: p.model ?? "", byDay: byDay, hourlyByDay: hourlyByDay)
    }

    private func scanCodex(days: Int, now: Date, into contributions: inout [Contribution],
                           fresh: inout [String: Contribution]) {
        let fm = FileManager.default
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let dayKey = String(format: "%04d-%02d-%02d", y, m, d)
            let dayDir = codexSessionsDir.appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", m))
                .appendingPathComponent(String(format: "%02d", d))
            guard SafeFileReader.isSafeDirectory(dayDir) else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                if let c = cached(file, fresh: &fresh, parse: { self.codexContribution($0, dayKey: dayKey) }) {
                    contributions.append(c)
                }
            }
        }
    }

    /// Codex: the file's cumulative total is attributed wholly to its date directory's day
    /// (a session spanning midnight lands on its start day — documented approximation).
    private func codexContribution(_ file: URL, dayKey: String) -> Contribution? {
        guard let p = LogFileParser.parseCodex(file) else { return nil }
        let total = p.buckets.values.reduce(TokenBreakdown(), +)
        guard total.total > 0 else { return nil }
        return Contribution(mtime: .distantPast, size: 0, provider: .codex,
                            project: URL(fileURLWithPath: p.folder).lastPathComponent,
                            model: p.model ?? "", byDay: [dayKey: total], hourlyByDay: [:])
    }
}
