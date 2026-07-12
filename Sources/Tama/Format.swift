import SwiftUI
import TamaCore

// Shared row/number formatting for the dashboard + usage section.

func providerTint(_ p: Provider) -> Color {
    switch p {
    case .claudeCode: return Palette.coral
    case .codex: return Palette.green
    case .gemini: return Palette.blue
    case .antigravity: return Palette.purple
    }
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

/// Estimated cost, prefixed with `~` to read as an estimate. Empty for zero (e.g. Gemini).
func formatCost(_ d: Double) -> String {
    if d <= 0 { return "" }
    if d < 0.01 { return "~<$0.01" }
    if d >= 1_000 { return String(format: "~$%.1fk", d / 1_000) }
    if d >= 100 { return String(format: "~$%.0f", d) }
    return String(format: "~$%.2f", d)
}

/// The shared caveat: these are public API rates, not the user's actual (often subscription) bill.
let costCaveat = "Estimated pay-as-you-go API cost from public per-token rates — "
    + "not your actual bill (Max/Pro subscriptions are billed differently). "
    + "May read slightly under Claude's /cost, which also counts interrupted/in-flight turns "
    + "not yet saved to the logs Tama reads."
