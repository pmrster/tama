import SwiftUI
import AppKit
import TamaCore

/// SwiftUI-facing settings: publishes the user's appearance/font choices, persists them via
/// `SettingsStore`, and applies appearance app-wide through `NSApp.appearance` (more reliable
/// for the menu-bar popover and floating panels than per-view `preferredColorScheme`).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store: SettingsStore

    @Published var appearance: Appearance { didSet { store.appearance = appearance; applyAppearance() } }
    @Published var fontSize: FontSize     { didSet { store.fontSize = fontSize } }

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.appearance = store.appearance
        self.fontSize = store.fontSize
    }

    /// nil = follow the OS; otherwise force light/dark. Used by SwiftUI previews/snapshots.
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var fontScale: Double { fontSize.factor }

    /// The AppKit appearance for the current setting (nil = follow the OS). Drives both
    /// `NSApp.appearance` and surfaces that don't inherit it (notably `NSPopover`).
    var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// Force (or clear) the whole app's appearance. Call at launch and on every change.
    func applyAppearance() {
        NSApp.appearance = nsAppearance
    }
}
