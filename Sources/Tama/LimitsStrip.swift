import SwiftUI
import TamaCore

/// Its own top-level "LIMITS" section (bracketed by dividers, like the tree): per provider account,
/// how much of the subscription's session (5h) and weekly window is used. Each account is a header
/// line — who it is (label · email · plan) — followed by one row per window: label, a fill bar, the
/// used %, and the reset countdown. A snapshot older than 15 min dims the whole account and shows an
/// "as of …" note; a window whose reset has passed reads "reset" instead of a stale number. The
/// section (and its leading divider) disappear entirely when no quota is known.
struct LimitsStrip: View {
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject private var settings = AppSettings.shared

    private var now: Date { monitor.state.lastUpdated }
    private var collapsed: Bool { settings.limitsCollapsed }

    var body: some View {
        if settings.showLimits && !monitor.state.quotas.isEmpty {
            Divider().overlay(Palette.panelEdge)
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    settings.limitsCollapsed.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: scaled(8), weight: .bold)).foregroundStyle(Palette.dim)
                        Text("LIMITS")
                            .font(.system(size: scaled(10), weight: .heavy)).tracking(1)
                            .foregroundStyle(Palette.dim)
                        Spacer(minLength: 8)
                        if collapsed {
                            Text("\(monitor.state.quotas.count) account\(monitor.state.quotas.count == 1 ? "" : "s")")
                                .font(.system(size: scaled(9), design: .monospaced)).foregroundStyle(Palette.dim)
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Show plan limits" : "Collapse plan limits (hide entirely in Settings)")
                if !collapsed {
                    ForEach(monitor.state.quotas) { account($0) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func account(_ q: AccountQuota) -> some View {
        let tint = providerTint(q.provider)
        let stale = QuotaFormat.staleness(fetchedAt: q.fetchedAt, now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 8, height: 8)
                Text(QuotaFormat.title(q))
                    .font(.system(size: scaled(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1).truncationMode(.middle)
                if let stale {
                    Text(stale).font(.system(size: scaled(8.5), design: .monospaced))
                        .foregroundStyle(Palette.dim).fixedSize()
                }
                Spacer(minLength: 0)
            }
            ForEach(Array(q.windows.enumerated()), id: \.offset) { _, w in
                windowRow(w, tint: tint)
            }
        }
        .opacity(stale != nil ? 0.6 : 1)
        .help(help(q))
    }

    private func windowRow(_ w: QuotaWindow, tint: Color) -> some View {
        let expired = w.isExpired(at: now)
        let frac = expired ? 0 : w.usedPercent / 100
        let color: Color = w.usedPercent >= 90 ? Palette.warn : (w.usedPercent >= 70 ? Palette.yellow : tint)
        return HStack(spacing: 8) {
            Text(w.kind.label)
                .font(.system(size: scaled(9.5), design: .monospaced))
                .foregroundStyle(Palette.dim)
                .frame(width: scaled(26), alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track).frame(width: 64, height: 5)
                Capsule().fill(expired ? Palette.dim : color)
                    .frame(width: max(frac > 0 ? 3 : 0, 64 * frac), height: 5)
            }
            Text(expired ? "—" : QuotaFormat.percent(w.usedPercent))
                .font(.system(size: scaled(10.5), weight: .semibold, design: .monospaced))
                .foregroundStyle(expired ? Palette.dim : color)
                .frame(width: scaled(46), alignment: .leading)
            if let reset = QuotaFormat.resetLabel(w, now: now) {
                Text(reset)
                    .font(.system(size: scaled(9), design: .monospaced))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
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
