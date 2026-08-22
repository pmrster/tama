import Foundation

/// Forced appearance. `system` follows the OS.
public enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark
}

/// Text-size preset. `factor` multiplies every hardcoded point size; `small` = 1.0 so the
/// app is pixel-identical to its original size, and the presets only grow from there.
public enum FontSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var factor: Double {
        switch self {
        case .small:  return 1.0
        case .medium: return 1.15
        case .large:  return 1.3
        }
    }
}

/// The user's visual preferences, persisted in `UserDefaults`. Pure value logic — no
/// SwiftUI/AppKit — with the defaults store injected so it is testable in isolation.
/// Unknown/missing stored values fall back to the defaults (`system`, `small`).
public struct SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let appearance = "tama.appearance"
        static let fontSize = "tama.fontSize"
        static let notifyAgentQuiet = "tama.notifyAgentQuiet"
        static let notifyContextHigh = "tama.notifyContextHigh"
        static let extraAccounts = "tama.extraAccounts"
        static let showLimits = "tama.showLimits"
        static let limitsCollapsed = "tama.limitsCollapsed"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var appearance: Appearance {
        get { defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    public var fontSize: FontSize {
        get { defaults.string(forKey: Key.fontSize).flatMap(FontSize.init(rawValue:)) ?? .small }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.fontSize) }
    }

    /// Alert when a streaming agent goes quiet (likely waiting for input). Off by default —
    /// the system notification-permission prompt only ever appears after a user opt-in.
    public var notifyAgentQuiet: Bool {
        get { defaults.bool(forKey: Key.notifyAgentQuiet) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifyAgentQuiet) }
    }

    /// Warn when a session's context window passes 85% (compaction imminent). Off by default.
    public var notifyContextHigh: Bool {
        get { defaults.bool(forKey: Key.notifyContextHigh) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifyContextHigh) }
    }

    /// Whether the plan-limits (session/weekly quota) section is shown at all. On by default;
    /// turning it off hides the whole section regardless of collapse state.
    public var showLimits: Bool {
        get { defaults.object(forKey: Key.showLimits) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.showLimits) }
    }

    /// Whether the plan-limits section is collapsed to just its header. Off by default; persisted
    /// so a user who collapses it keeps it that way across launches.
    public var limitsCollapsed: Bool {
        get { defaults.bool(forKey: Key.limitsCollapsed) }
        nonmutating set { defaults.set(newValue, forKey: Key.limitsCollapsed) }
    }

    /// Additional provider accounts — config dirs the agents were pointed at via
    /// `CLAUDE_CONFIG_DIR` / `CODEX_HOME`. Stored as JSON; anything unreadable reads as none.
    public var extraAccounts: [AccountRoot] {
        get {
            guard let s = defaults.string(forKey: Key.extraAccounts), let data = s.data(using: .utf8),
                  let roots = try? JSONDecoder().decode([AccountRoot].self, from: data) else { return [] }
            return roots
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue), let s = String(data: data, encoding: .utf8) {
                defaults.set(s, forKey: Key.extraAccounts)
            }
        }
    }

    /// Every account the readers should scan: the standard `~/.claude` / `~/.codex` first, then
    /// the user's extras in the order they were added.
    public func accountRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AccountRoot] {
        AccountRoot.defaults(home: home) + extraAccounts
    }
}
