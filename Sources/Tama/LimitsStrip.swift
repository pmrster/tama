import SwiftUI
import TamaCore

/// Plan limits per provider account: one compact row per `AccountQuota` — provider dot, who the
/// account is, then a mini gauge per window (5h / wk / per-model) with the used share. Hidden
/// when nothing is known. Reset countdown, data age and source live in the row's tooltip; a row
/// whose snapshot is older than 15 minutes is dimmed, and a window whose reset has already
/// passed shows "reset" instead of a stale percentage.
struct LimitsStrip: View {
    @ObservedObject var monitor: AgentMonitor

    private var now: Date { monitor.state.lastUpdated }

    var body: some View {
        if !monitor.state.quotas.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.state.quotas) { row($0) }
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        }
    }

    private func row(_ q: AccountQuota) -> some View {
        let tint = providerTint(q.provider)
        let stale = QuotaFormat.staleness(fetchedAt: q.fetchedAt, now: now) != nil
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 8, height: 8)
            Text(QuotaFormat.title(q, compact: true))
                .font(.system(size: scaled(9.5), design: .monospaced))
                .foregroundStyle(Palette.dim)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            ForEach(Array(q.windows.enumerated()), id: \.offset) { _, w in
                gauge(w, tint: tint)
            }
        }
        .opacity(stale ? 0.55 : 1)
        .help(help(q))
    }

    private func gauge(_ w: QuotaWindow, tint: Color) -> some View {
        let expired = w.isExpired(at: now)
        let frac = expired ? 0 : w.usedPercent / 100
        let color: Color = w.usedPercent >= 90 ? Palette.warn : (w.usedPercent >= 70 ? Palette.yellow : tint)
        return HStack(spacing: 3) {
            Text(w.kind.label)
                .font(.system(size: scaled(8), design: .monospaced))
                .foregroundStyle(Palette.dim)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track).frame(width: 22, height: 4)
                Capsule().fill(expired ? Palette.dim : color)
                    .frame(width: max(frac > 0 ? 2 : 0, 22 * frac), height: 4)
            }
            Text(expired ? "reset" : QuotaFormat.percent(w.usedPercent))
                .font(.system(size: scaled(10), weight: .semibold, design: .monospaced))
                .foregroundStyle(expired ? Palette.dim : color)
        }
        .fixedSize()
    }

    private func help(_ q: AccountQuota) -> String {
        var lines = ["\(q.provider.displayName) plan limits — \(QuotaFormat.title(q))"]
        for w in q.windows {
            var l = "\(windowName(w.kind)): \(QuotaFormat.percent(w.usedPercent)) used"
            if let r = w.resetsAt {
                l += w.isExpired(at: now)
                    ? " (window reset \(QuotaFormat.countdown(to: now, from: r)) ago — awaiting a fresh reading)"
                    : ", resets in \(QuotaFormat.countdown(to: r, from: now))"
            }
            lines.append(l)
        }
        if let s = QuotaFormat.staleness(fetchedAt: q.fetchedAt, now: now) { lines.append("Data \(s).") }
        lines.append(sourceNote(q.source))
        return lines.joined(separator: "\n")
    }

    private func windowName(_ k: QuotaWindow.Kind) -> String {
        switch k {
        case .session: return "Session (5h)"
        case .weekly: return "Weekly"
        case .scoped(let s): return "Weekly \(s)"
        }
    }

    private func sourceNote(_ s: QuotaSource) -> String {
        switch s {
        case .codexLog: return "From Codex's own rate-limit record in its session log (updated every turn)."
        case .claudeConfigCache: return "From Claude Code's cached /usage snapshot in .claude.json — refreshed on Claude's schedule, so it can lag; run /usage in Claude Code to refresh."
        case .claudeStatusline: return "From the status-line data Claude Code streams to your statusline bridge (live)."
        }
    }
}
