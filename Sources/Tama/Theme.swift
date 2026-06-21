import SwiftUI
import AppKit

extension Color {
    /// An appearance-adaptive color: resolves to `light` or `dark` (each `0xRRGGBB`) based on
    /// the view's effective appearance. One `Palette` constant then works in both modes and
    /// re-resolves when the app appearance is forced (see `AppSettings.applyAppearance`).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
                           green: Double((hex >> 8) & 0xFF) / 255.0,
                           blue: Double(hex & 0xFF) / 255.0,
                           alpha: 1.0)
        })
    }
}

/// Multiplies a hardcoded point size by the current font-size factor. Reading the shared
/// settings here keeps each of the ~60 call sites a one-token change; views that observe
/// `AppSettings.shared` re-evaluate their bodies (and so recompute sizes) when it changes.
@MainActor
func scaled(_ size: CGFloat) -> CGFloat { size * CGFloat(AppSettings.shared.fontScale) }
