import Foundation

/// Renders a CLIReport as a human-readable, grouped-by-project table. Pure string output;
/// `color: false` yields plain ASCII (used by tests). The dash "—" marks data a provider
/// does not expose (Gemini/Antigravity tokens & context).
public enum TableRenderer {
    public static func render(_ report: CLIReport, color: Bool) -> String {
        var out = ""

        // Provider totals block.
        for pt in report.providers {
            let name = bold(providerDisplayName(pt.provider), color)
            let tok = pt.todayTokens > 0 ? formatTokens(pt.todayTokens) + " tok" : "—"
            out += "\(name)  \(pt.activeCount) active  \(tok) · \(formatCost(pt.todayCost))\n"
        }
        if !report.providers.isEmpty { out += "\n" }

        // Projects / sessions block.
        if report.projects.isEmpty {
            out += "No active sessions.\n"
            return out
        }
        for proj in report.projects {
            out += "\(bold(proj.project, color))  \(dim("(\(proj.folder))", color))\n"
            for s in proj.sessions {
                let marker = s.active ? "●" : "○"
                let short = providerShort(s.provider)
                let model = s.model ?? "—"
                let tok = s.tokens.map(formatTokens) ?? "—"
                let ctx = s.contextFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
                out += "  \(marker) \(pad(s.name, 20)) \(pad(short, 3)) \(pad(model, 8)) "
                out += "\(pad(tok, 8)) ctx \(pad(ctx, 4)) \(formatCost(s.cost))\n"
            }
        }
        return out
    }

    // MARK: formatting

    static func formatTokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 {
            let v = Double(n) / 1000
            return v < 10 ? String(format: "%.1fk", v) : String(format: "%.0fk", v)
        }
        return String(format: "%.2fM", Double(n) / 1_000_000)
    }

    static func formatCost(_ c: Double) -> String { String(format: "$%.2f", c) }

    static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    static func providerDisplayName(_ raw: String) -> String {
        Provider(rawValue: raw)?.displayName ?? raw
    }
    static func providerShort(_ raw: String) -> String {
        Provider(rawValue: raw)?.shortName ?? raw
    }

    // MARK: ANSI (no-op when color is off)

    static func bold(_ s: String, _ color: Bool) -> String { color ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
    static func dim(_ s: String, _ color: Bool) -> String { color ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
}
