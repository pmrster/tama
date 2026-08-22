import Foundation

/// One rate-limit window of a subscription plan — how much of the allowance is used and when
/// it rolls over. `session` is the rolling ~5-hour window, `weekly` the 7-day one; `scoped` is a
/// provider-specific extra (e.g. Claude's per-model weekly cap, labelled "Opus").
public struct QuotaWindow: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case session
        case weekly
        case scoped(String)

        /// Short label for the gauge.
        public var label: String {
            switch self {
            case .session: return "5h"
            case .weekly: return "wk"
            case .scoped(let s): return s
            }
        }
        /// Display order: session, weekly, then scoped extras.
        var order: Int {
            switch self {
            case .session: return 0
            case .weekly: return 1
            case .scoped: return 2
            }
        }
    }

    public let kind: Kind
    /// Used share of the allowance, clamped to 0…100.
    public let usedPercent: Double
    /// When the window rolls over; nil when the provider didn't say (typically an idle window).
    public let resetsAt: Date?

    public init(kind: Kind, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { 100 - usedPercent }

    /// True once the reset time has passed — the data predates the current window and no
    /// longer describes live usage (the UI dims it).
    public func isExpired(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt < now
    }
}

/// Where a quota snapshot came from — decides how fresh it can be.
public enum QuotaSource: String, Sendable, Equatable {
    /// Codex writes its rate limits into every `token_count` event → fresh as of the last turn.
    case codexLog
    /// Claude Code's own `/usage` cache in `.claude.json` — refreshed on its schedule, can be stale.
    case claudeConfigCache
    /// Status-line JSON mirrored to a file by the user's statusline command (opt-in bridge).
    case claudeStatusline
}

/// One account's plan-limit snapshot for a provider.
public struct AccountQuota: Sendable, Equatable, Identifiable {
    public let provider: Provider
    /// The account root's label (nil = the default config dir / the only account).
    public let label: String?
    /// Stable key for the account (Claude `accountUuid`; Codex has none → the root label).
    public let accountKey: String
    /// Human identity when the provider exposes one without reading credentials (Claude email).
    public let identity: String?
    /// Plan name, prettified ("Max 5x", "Plus"); nil if unknown.
    public let plan: String?
    /// Windows in display order (session, weekly, scoped…).
    public let windows: [QuotaWindow]
    /// When the source data was produced (the event time / cache fetch time / bridge mtime).
    public let fetchedAt: Date
    public let source: QuotaSource

    public var id: String { "\(provider.rawValue):\(label ?? ""):\(accountKey)" }

    public init(provider: Provider, label: String?, accountKey: String, identity: String?, plan: String?,
                windows: [QuotaWindow], fetchedAt: Date, source: QuotaSource) {
        self.provider = provider; self.label = label; self.accountKey = accountKey
        self.identity = identity; self.plan = plan
        self.windows = windows.sorted { $0.kind.order < $1.kind.order }
        self.fetchedAt = fetchedAt; self.source = source
    }

    /// Codex `plan_type` ("plus", "pro", "team") → "Plus".
    public static func prettyPlan(codex raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Claude `organizationType` ("claude_max") + `organizationRateLimitTier`
    /// ("default_claude_max_5x") → "Max 5x". The tier's trailing multiplier is the only part
    /// that adds information beyond the org type.
    public static func prettyPlan(claudeOrgType: String?, tier: String?) -> String? {
        guard let claudeOrgType, !claudeOrgType.isEmpty else { return nil }
        var name = claudeOrgType
        if name.hasPrefix("claude_") { name.removeFirst("claude_".count) }
        name = name.replacingOccurrences(of: "_", with: " ").capitalized
        if let tier, let last = tier.split(separator: "_").last, last.hasSuffix("x"),
           Int(last.dropLast()) != nil {
            name += " \(last)"
        }
        return name
    }
}
