import Foundation

/// One provider account's on-disk home — what `CLAUDE_CONFIG_DIR` / `CODEX_HOME` point at.
/// The default account is the provider's standard dir (`~/.claude`, `~/.codex`); extra accounts
/// are user-configured dirs the same tools were pointed at. Every reader takes a list of these so
/// sessions, history and plan limits can be attributed per account.
public struct AccountRoot: Sendable, Equatable, Hashable, Identifiable {
    public let provider: Provider
    /// Short user-facing name (nil = the default account; the UI omits the suffix).
    public let label: String?
    /// The config dir itself.
    public let root: URL
    /// Claude only: the `.claude.json` that holds the account + cached `/usage` snapshot. Inside the
    /// config dir when `CLAUDE_CONFIG_DIR` is set, but a *sibling* of `~/.claude` for the default.
    public let configFile: URL?

    public var id: String { "\(provider.rawValue):\(root.path)" }

    public init(provider: Provider, label: String?, root: URL, configFile: URL? = nil) {
        self.provider = provider
        self.label = label?.isEmpty == true ? nil : label
        self.root = root
        switch provider {
        case .claudeCode: self.configFile = configFile ?? root.appendingPathComponent(".claude.json")
        default: self.configFile = nil
        }
    }

    /// `<root>/projects` (Claude) — where session logs live.
    public var claudeProjectsDir: URL { root.appendingPathComponent("projects") }
    /// `<root>/sessions` (Codex) — where rollouts live.
    public var codexSessionsDir: URL { root.appendingPathComponent("sessions") }

    /// The standard `~/.claude` and `~/.codex` accounts.
    public static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AccountRoot] {
        [AccountRoot(provider: .claudeCode, label: nil, root: home.appendingPathComponent(".claude"),
                     configFile: home.appendingPathComponent(".claude.json")),
         AccountRoot(provider: .codex, label: nil, root: home.appendingPathComponent(".codex"))]
    }
}
