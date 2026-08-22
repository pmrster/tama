import Foundation

/// Text formatting for the plan-limits strip. Pure, so the shell stays thin and this is tested.
public enum QuotaFormat {
    /// "5d 3h", "2h 10m", "<1m", or "now" once the moment has passed. At most two units.
    public static func countdown(to target: Date, from now: Date) -> String {
        let secs = Int(target.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        if secs < 60 { return "<1m" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// "as of 40m ago" once the snapshot is older than 15 minutes; nil while it's fresh.
    public static func staleness(fetchedAt: Date, now: Date) -> String? {
        let age = now.timeIntervalSince(fetchedAt)
        if age < 15 * 60 { return nil }
        if fetchedAt == .distantPast || age > 365 * 86400 { return "as of unknown time" }
        return "as of \(countdown(to: now, from: fetchedAt)) ago"
    }

    /// Row title: the parts the account exposes, joined — label · identity · plan. "default" if none.
    /// `compact` trims an email identity to its local part (the strip is narrow; the tooltip has it all).
    public static func title(_ q: AccountQuota, compact: Bool = false) -> String {
        var identity = q.identity
        if compact, let at = identity?.firstIndex(of: "@"), at != identity?.startIndex {
            identity = String(identity![..<at])
        }
        let parts = [q.label, identity, q.plan].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "default" : parts.joined(separator: " · ")
    }

    /// The reset hint for a window: "resets 2h 10m", "reset" once the window has rolled over,
    /// or nil when the provider gave no reset time.
    public static func resetLabel(_ w: QuotaWindow, now: Date) -> String? {
        guard let r = w.resetsAt else { return nil }
        return w.isExpired(at: now) ? "reset" : "resets \(countdown(to: r, from: now))"
    }

    /// "46%" / "12.5%" — one decimal only when it carries information.
    public static func percent(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))%" }
        return String(format: "%.1f%%", rounded)
    }
}
