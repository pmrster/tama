import Foundation

/// Something that can produce the per-account plan-limit snapshots (the reader, or a test mock).
public protocol QuotaScanning: Sendable {
    func scanQuotas() -> [AccountQuota]
}

/// Reads each account's plan limits (session / weekly utilisation) from what the agents already
/// leave on disk — no network, no credentials:
///
/// - **Codex**: every `token_count` event in a rollout carries `rate_limits`; the last one in the
///   most recently written rollout is the live figure. Only the file's tail is read.
/// - **Claude Code**: `.claude.json` holds Claude's own `/usage` cache (`cachedUsageUtilization`)
///   next to the logged-in `oauthAccount`. Only those two keys are used; the rest of the file
///   (notably per-project prompt history) is never retained.
///
/// Parsing is cached per file by (mtime, size). Strictly read-only.
public final class QuotaReader: QuotaScanning, @unchecked Sendable {
    private let rootsProvider: () -> [AccountRoot]
    private let statuslineDir: URL?
    private let now: () -> Date
    private let calendar: Calendar

    /// Day-folders to look back for the newest Codex rollout (a long-lived session keeps
    /// appending to a file under its START date).
    private let codexLookbackDays = 14
    /// How many newest rollouts to try before giving up (a just-started session has no limits yet).
    private let codexCandidates = 5
    private let codexTailBytes = 256 * 1024
    private let claudeConfigMaxBytes = 64 * 1024 * 1024

    private struct Cached<T> { let mtime: Date; let size: Int; let value: T }
    private var codexCache: [String: Cached<CodexLimits?>] = [:]
    private var claudeCache: [String: Cached<ClaudeSnapshot?>] = [:]
    private let lock = NSLock()

    /// `roots` is consulted on every scan so accounts added in Settings take effect at once.
    /// `statuslineDir` (opt-in bridge) holds per-account `<label>.json` files a user's Claude Code
    /// statusline command writes with the live `rate_limits` block; when one is fresher than the
    /// cached snapshot for its account, its windows win.
    public init(roots: @escaping () -> [AccountRoot], statuslineDir: URL? = nil,
                now: @escaping () -> Date, calendar: Calendar = .current) {
        self.rootsProvider = roots
        self.statuslineDir = statuslineDir
        self.now = now
        self.calendar = calendar
    }

    /// Fixed-roots convenience (tests).
    public convenience init(roots: [AccountRoot], statuslineDir: URL? = nil,
                            now: @escaping () -> Date, calendar: Calendar = .current) {
        self.init(roots: { roots }, statuslineDir: statuslineDir, now: now, calendar: calendar)
    }

    public convenience init(now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.init(roots: { AccountRoot.defaults() }, statuslineDir: Self.defaultStatuslineDir(),
                  now: now, calendar: calendar)
    }

    /// `~/Library/Application Support/Tama/statusline` — where the opt-in bridge files live.
    public static func defaultStatuslineDir(
        appSupport: URL? = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                        in: .userDomainMask, appropriateFor: nil, create: false)) -> URL? {
        appSupport?.appendingPathComponent("Tama/statusline")
    }

    public func scanQuotas() -> [AccountQuota] {
        lock.lock(); defer { lock.unlock() }
        var out: [AccountQuota] = []
        for root in rootsProvider() {
            switch root.provider {
            case .codex: if let q = codexQuota(root) { out.append(q) }
            case .claudeCode: if let q = claudeQuota(root) { out.append(q) }
            default: continue
            }
        }
        return out.sorted {
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return ($0.label ?? "") < ($1.label ?? "")
        }
    }

    // MARK: Codex

    struct CodexLimits {
        let plan: String?
        let windows: [QuotaWindow]
        let at: Date
    }

    private func codexQuota(_ root: AccountRoot) -> AccountQuota? {
        let fm = FileManager.default
        let today = now()
        var candidates: [(URL, Date)] = []
        for dayOffset in 0..<codexLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let dayDir = root.codexSessionsDir.appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", m)).appendingPathComponent(String(format: "%02d", d))
            guard SafeFileReader.isSafeDirectory(dayDir),
                  let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for f in files where f.lastPathComponent.hasPrefix("rollout-") && f.pathExtension == "jsonl" {
                if let mod = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    candidates.append((f, mod))
                }
            }
        }
        candidates.sort { $0.1 > $1.1 }
        for (file, _) in candidates.prefix(codexCandidates) {
            guard let limits = cachedCodex(file) else { continue }
            return AccountQuota(provider: .codex, label: root.label, accountKey: root.label ?? "default",
                                identity: nil, plan: AccountQuota.prettyPlan(codex: limits.plan),
                                windows: limits.windows, fetchedAt: limits.at, source: .codexLog)
        }
        return nil
    }

    private func cachedCodex(_ file: URL) -> CodexLimits? {
        guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = vals.contentModificationDate, let size = vals.fileSize else { return nil }
        if let hit = codexCache[file.path], hit.mtime == mtime, hit.size == size { return hit.value }
        let parsed = Self.parseCodexLimits(tail: SafeFileReader.tail(at: file, maxBytes: codexTailBytes), mtime: mtime)
        codexCache[file.path] = Cached(mtime: mtime, size: size, value: parsed)
        return parsed
    }

    /// The LAST `rate_limits` block in the given tail. A tail may start mid-line; that partial
    /// first line simply fails to parse and is skipped.
    static func parseCodexLimits(tail: Data?, mtime: Date) -> CodexLimits? {
        guard let tail else { return nil }
        var result: CodexLimits?
        SafeFileReader.forEachLineData(in: tail) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let rl = payload["rate_limits"] as? [String: Any] else { return }
            var windows: [QuotaWindow] = []
            for key in ["primary", "secondary"] {
                guard let w = rl[key] as? [String: Any],
                      let used = Self.number(w["used_percent"]) else { continue }
                let minutes = Int(Self.number(w["window_minutes"]) ?? 0)
                let kind: QuotaWindow.Kind
                switch minutes {
                case 0..<1440: kind = .session
                case 10080: kind = .weekly
                default: kind = .scoped("\(minutes / 1440)d")
                }
                let resets = Self.number(w["resets_at"]).map { Date(timeIntervalSince1970: $0) }
                windows.append(QuotaWindow(kind: kind, usedPercent: used, resetsAt: resets))
            }
            guard !windows.isEmpty else { return }
            let at = (obj["timestamp"] as? String).flatMap(Self.parseDate) ?? mtime
            result = CodexLimits(plan: rl["plan_type"] as? String, windows: windows, at: at)
        }
        return result
    }

    // MARK: Claude

    struct ClaudeSnapshot {
        let accountKey: String
        let identity: String?
        let plan: String?
        let windows: [QuotaWindow]
        let fetchedAt: Date
    }

    private func claudeQuota(_ root: AccountRoot) -> AccountQuota? {
        guard let cfg = root.configFile, let snap = cachedClaude(cfg) else { return nil }
        // Opt-in bridge: a `<label>.json` (default → "default.json") the statusline command writes.
        // When it's newer than the cached snapshot, its live windows replace the cached ones;
        // identity/plan still come from `.claude.json` (the bridge JSON carries neither).
        if let bridge = statuslineBridge(label: root.label), bridge.fetchedAt > snap.fetchedAt {
            return AccountQuota(provider: .claudeCode, label: root.label, accountKey: snap.accountKey,
                                identity: snap.identity, plan: snap.plan, windows: bridge.windows,
                                fetchedAt: bridge.fetchedAt, source: .claudeStatusline)
        }
        return AccountQuota(provider: .claudeCode, label: root.label, accountKey: snap.accountKey,
                            identity: snap.identity, plan: snap.plan, windows: snap.windows,
                            fetchedAt: snap.fetchedAt, source: .claudeConfigCache)
    }

    private func statuslineBridge(label: String?) -> (windows: [QuotaWindow], fetchedAt: Date)? {
        guard let dir = statuslineDir else { return nil }
        let file = dir.appendingPathComponent("\(label ?? "default").json")
        guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
              let mtime = vals.contentModificationDate,
              let windows = Self.parseStatusline(SafeFileReader.data(at: file, maxBytes: 1_048_576)),
              !windows.isEmpty else { return nil }
        return (windows, mtime)
    }

    /// The documented Claude Code status-line `rate_limits` block:
    /// `{ five_hour:{used_percentage, resets_at(epoch s)}, seven_day:{…} }`.
    static func parseStatusline(_ data: Data?) -> [QuotaWindow]? {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limits"] as? [String: Any] else { return nil }
        func window(_ key: String, _ kind: QuotaWindow.Kind) -> QuotaWindow? {
            guard let w = rl[key] as? [String: Any],
                  let used = Self.number(w["used_percentage"]) ?? Self.number(w["used_percent"]) else { return nil }
            return QuotaWindow(kind: kind, usedPercent: used,
                               resetsAt: Self.number(w["resets_at"]).map { Date(timeIntervalSince1970: $0) })
        }
        return [window("five_hour", .session), window("seven_day", .weekly)].compactMap { $0 }
    }

    private func cachedClaude(_ file: URL) -> ClaudeSnapshot? {
        guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = vals.contentModificationDate, let size = vals.fileSize else { return nil }
        if let hit = claudeCache[file.path], hit.mtime == mtime, hit.size == size { return hit.value }
        let parsed = Self.parseClaudeConfig(SafeFileReader.data(at: file, maxBytes: claudeConfigMaxBytes))
        claudeCache[file.path] = Cached(mtime: mtime, size: size, value: parsed)
        return parsed
    }

    /// Pulls `oauthAccount` + `cachedUsageUtilization` out of a `.claude.json`; everything else
    /// in the file is ignored. Nil when there is no cached utilisation to show.
    static func parseClaudeConfig(_ data: Data?) -> ClaudeSnapshot? {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = obj["cachedUsageUtilization"] as? [String: Any],
              let util = cache["utilization"] as? [String: Any] else { return nil }
        let account = obj["oauthAccount"] as? [String: Any]
        func window(_ key: String, _ kind: QuotaWindow.Kind) -> QuotaWindow? {
            guard let w = util[key] as? [String: Any], let used = Self.number(w["utilization"]) else { return nil }
            return QuotaWindow(kind: kind, usedPercent: used,
                               resetsAt: (w["resets_at"] as? String).flatMap(Self.parseDate))
        }
        let windows = [window("five_hour", .session), window("seven_day", .weekly),
                       window("seven_day_opus", .scoped("Opus")), window("seven_day_sonnet", .scoped("Sonnet"))]
            .compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        let fetched = Self.number(cache["fetchedAtMs"]).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
        let key = (cache["accountUuid"] as? String) ?? (account?["accountUuid"] as? String) ?? "default"
        return ClaudeSnapshot(accountKey: key, identity: account?["emailAddress"] as? String,
                              plan: AccountQuota.prettyPlan(claudeOrgType: account?["organizationType"] as? String,
                                                            tier: account?["organizationRateLimitTier"] as? String),
                              windows: windows, fetchedAt: fetched)
    }

    // MARK: helpers

    private static func number(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        default: return nil
        }
    }

    /// ISO 8601 with any number of fractional digits (Claude writes 6, the shared formatter
    /// accepts exactly 3) or none at all.
    static func parseDate(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter.shared.date(from: s) { return d }
        // Trim/pad the fraction to 3 digits: "…:00.464148+00:00" → "…:00.464+00:00".
        guard let dot = s.firstIndex(of: ".") else {
            return ISO8601DateFormatter.noFraction.date(from: s)
        }
        var end = s.index(after: dot)
        while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
        let digits = String(s[s.index(after: dot)..<end])
        let frac = String((digits + "000").prefix(3))
        return ISO8601DateFormatter.shared.date(from: String(s[..<dot]) + "." + frac + String(s[end...]))
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let noFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
