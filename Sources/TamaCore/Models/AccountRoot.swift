import Foundation

/// One provider account's on-disk home — what `CLAUDE_CONFIG_DIR` / `CODEX_HOME` point at.
/// The default account is the provider's standard dir (`~/.claude`, `~/.codex`); extra accounts
/// are user-configured dirs the same tools were pointed at. Every reader takes a list of these so
/// sessions, history and plan limits can be attributed per account.
public struct AccountRoot: Sendable, Equatable, Hashable, Identifiable, Codable {
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

    // Persisted as {provider, label, root, configFile} — `root`/`configFile` as file paths.
    private enum CodingKeys: String, CodingKey { case provider, label, root, configFile }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try c.decode(Provider.self, forKey: .provider)
        let root = URL(fileURLWithPath: try c.decode(String.self, forKey: .root))
        let cfg = try c.decodeIfPresent(String.self, forKey: .configFile).map { URL(fileURLWithPath: $0) }
        self.init(provider: provider, label: try c.decodeIfPresent(String.self, forKey: .label), root: root, configFile: cfg)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(root.path, forKey: .root)
        try c.encodeIfPresent(configFile?.path, forKey: .configFile)
    }

    /// The standard `~/.claude` and `~/.codex` accounts.
    public static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AccountRoot] {
        [AccountRoot(provider: .claudeCode, label: nil, root: home.appendingPathComponent(".claude"),
                     configFile: home.appendingPathComponent(".claude.json")),
         AccountRoot(provider: .codex, label: nil, root: home.appendingPathComponent(".codex"))]
    }
}
