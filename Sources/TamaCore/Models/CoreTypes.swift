import Foundation

public enum Provider: String, CaseIterable, Sendable {
    case claudeCode
    case codex
    case gemini
    case antigravity

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .antigravity: return "Antigravity"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode: return "CC"
        case .codex: return "CX"
        case .gemini: return "GE"
        case .antigravity: return "AG"
        }
    }

    /// Whether per-session token/model data is available from local logs for this provider.
    public var hasUsageData: Bool {
        switch self {
        case .claudeCode, .codex: return true
        case .gemini, .antigravity: return false
        }
    }
}

/// Which time window the displayed token/cost totals cover.
/// - `today`: since local midnight (matches the providers' daily usage reset).
/// - `last24h`: the trailing 24 hours (no midnight cliff; also surfaces yesterday-evening work).
public enum TokenWindow: String, CaseIterable, Sendable {
    case today
    case last24h

    /// Short label for the header chip.
    public var label: String {
        switch self {
        case .today: return "Today"
        case .last24h: return "24h"
        }
    }
}

public enum Location: String, CaseIterable, Sendable {
    case terminal
    case ide
    case desktop
}

public struct ProcInfo: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let execPath: String?
    public let argv: [String]
    public let cwd: String?
    public let hasTTY: Bool
    public let commName: String

    public init(pid: Int32, ppid: Int32, execPath: String?, argv: [String],
                cwd: String?, hasTTY: Bool, commName: String) {
        self.pid = pid; self.ppid = ppid; self.execPath = execPath
        self.argv = argv; self.cwd = cwd; self.hasTTY = hasTTY; self.commName = commName
    }
}

public struct AgentSession: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let provider: Provider
    public let location: Location
    public let cwd: String?
    public var id: Int32 { pid }

    public init(pid: Int32, provider: Provider, location: Location, cwd: String?) {
        self.pid = pid; self.provider = provider; self.location = location; self.cwd = cwd
    }
}

public struct TokenBreakdown: Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    /// Subset of `cacheWrite` that used the 1-hour cache TTL (Claude's
    /// `cache_creation.ephemeral_1h_input_tokens`). Billed at 2× input vs the 5-minute rate's
    /// 1.25×, so cost prices this portion separately. Not added to `total` — it's part of cacheWrite.
    public var cacheWrite1h: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite; self.cacheWrite1h = cacheWrite1h
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(input: lhs.input + rhs.input,
                       output: lhs.output + rhs.output,
                       cacheRead: lhs.cacheRead + rhs.cacheRead,
                       cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
                       cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h)
    }
}

public struct ProjectUsage: Sendable, Equatable, Identifiable {
    public let project: String
    public let tokens: Int
    public let cost: Double
    public var id: String { project }
    public init(project: String, tokens: Int, cost: Double) {
        self.project = project; self.tokens = tokens; self.cost = cost
    }
}

public struct UsageStats: Sendable, Equatable {
    public let todayTokens: Int
    public let todayCost: Double
    public let byProject: [ProjectUsage]
    public init(todayTokens: Int, todayCost: Double, byProject: [ProjectUsage]) {
        self.todayTokens = todayTokens; self.todayCost = todayCost; self.byProject = byProject
    }
    public static let empty = UsageStats(todayTokens: 0, todayCost: 0, byProject: [])
}

/// A recently-active agent session, named by its project folder. The folder/project
/// comes from the agent's log file (`cwd`), since a process's working directory is not
/// readable from the process table without elevated privileges.
public struct SessionInfo: Sendable, Equatable, Identifiable {
    public let provider: Provider
    public let project: String       // folder basename, e.g. "tama-widget"
    public let folder: String        // full path, e.g. "/Example/Code/tama-widget"
    public let lastActivity: Date
    public let tokens: Int           // today's CUMULATIVE tokens for THIS session (incl. cache)
    public let cacheTokens: Int      // the cache portion of `tokens`
    public let contextTokens: Int    // current context-WINDOW occupancy (last turn's input side); 0 if unknown
    public let contextWindow: Int    // the model's max context window; 0 if unknown
    public let model: String?        // last model seen in this session today
    public let sessionId: String?    // short session id, e.g. "019eddab"
    public let title: String?        // human title from the log (Claude `summary`), if any
    public let messages: Int         // conversation length (user+assistant turns); matches Claude `/resume`
    /// Today's tokens split by type (input/output/cacheRead/cacheWrite). This is the basis for
    /// cost, since the four types are priced very differently; `tokens`/`cacheTokens` are the
    /// rolled-up display numbers and equal `breakdown.total` / its cache parts when populated.
    public let breakdown: TokenBreakdown
    /// Fresh (non-cache) tokens = input + output.
    public var freshTokens: Int { max(0, tokens - cacheTokens) }
    /// Estimated pay-as-you-go API cost of today's tokens for this session, per the given rates.
    public func cost(using estimator: CostEstimator) -> Double { estimator.cost(breakdown, provider: provider, model: model) }
    /// How full the context window is right now, 0...1, or nil if it can't be determined.
    /// NOTE: this is the live window occupancy, NOT the cumulative `tokens` used today —
    /// the two differ by orders of magnitude because every turn re-reads the whole context.
    public var contextFraction: Double? {
        guard contextWindow > 0, contextTokens > 0 else { return nil }
        return min(1, Double(contextTokens) / Double(contextWindow))
    }
    /// What to show as the session's name: its title if it has one, else the short id.
    public var displayName: String { title ?? sessionId ?? "session" }
    public var id: String { "\(provider.rawValue):\(folder):\(sessionId ?? "")" }
    public init(provider: Provider, project: String, folder: String, lastActivity: Date,
                tokens: Int = 0, cacheTokens: Int = 0, contextTokens: Int = 0, contextWindow: Int = 0,
                model: String? = nil, sessionId: String? = nil, title: String? = nil,
                breakdown: TokenBreakdown = TokenBreakdown(), messages: Int = 0) {
        self.provider = provider; self.project = project
        self.folder = folder; self.lastActivity = lastActivity
        self.tokens = tokens; self.cacheTokens = cacheTokens
        self.contextTokens = contextTokens; self.contextWindow = contextWindow
        self.model = model; self.sessionId = sessionId; self.title = title
        self.breakdown = breakdown; self.messages = messages
    }
}

public struct AppState: Sendable, Equatable {
    public let sessions: [AgentSession]
    public let usage: [Provider: UsageStats]
    public let lastUpdated: Date
    public let activeSessions: [SessionInfo]
    public init(sessions: [AgentSession], usage: [Provider: UsageStats], lastUpdated: Date,
                activeSessions: [SessionInfo] = []) {
        self.sessions = sessions; self.usage = usage; self.lastUpdated = lastUpdated
        self.activeSessions = activeSessions
    }
    public static let empty = AppState(sessions: [], usage: [:], lastUpdated: .distantPast)
}
