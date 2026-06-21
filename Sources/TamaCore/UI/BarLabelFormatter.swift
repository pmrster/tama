import Foundation

public enum BarLabelFormatter {
    /// Builds the menu-bar label like "CC 3 · CX 4". Zero-session providers are omitted.
    public static func label(for sessions: [AgentSession]) -> String {
        var counts: [Provider: Int] = [:]
        for s in sessions { counts[s.provider, default: 0] += 1 }
        let parts = Provider.allCases.compactMap { p -> String? in
            let c = counts[p] ?? 0
            return c > 0 ? "\(p.shortName) \(c)" : nil
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
