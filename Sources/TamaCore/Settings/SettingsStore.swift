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
}
