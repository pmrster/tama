import Foundation

/// One local day's token usage, split per provider by model and by project folder.
/// `day` is a "yyyy-MM-dd" key in the calendar/zone it was computed with; keys compare
/// lexicographically in date order. Project names come from log `cwd` values and are
/// DISPLAY ONLY — never build a filesystem path from them.
public struct DayUsage: Sendable, Equatable, Codable {
    public let day: String
    public var models: [Provider: [String: TokenBreakdown]]     // model id ("" = unknown) → tokens
    public var projects: [Provider: [String: TokenBreakdown]]   // folder basename → tokens

    public init(day: String,
                models: [Provider: [String: TokenBreakdown]] = [:],
                projects: [Provider: [String: TokenBreakdown]] = [:]) {
        self.day = day; self.models = models; self.projects = projects
    }

    /// Element-wise sum of several days, labelled with the given day key (used for window rollups).
    public static func sum(_ days: [DayUsage], as day: String) -> DayUsage {
        var out = DayUsage(day: day)
        for d in days {
            mergeInto(&out.models, d.models)
            mergeInto(&out.projects, d.projects)
        }
        return out
    }

    /// Adds every `TokenBreakdown` in `src` into the matching (provider, key) slot in `dst`.
    private static func mergeInto(_ dst: inout [Provider: [String: TokenBreakdown]],
                                   _ src: [Provider: [String: TokenBreakdown]]) {
        for (p, inner) in src {
            for (k, bd) in inner { dst[p, default: [:]][k] = (dst[p]?[k] ?? TokenBreakdown()) + bd }
        }
    }

    public var totalTokens: Int {
        models.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.total } }
    }

    /// The model with the most total tokens (ties broken arbitrarily), or nil if empty.
    public func topModel() -> (provider: Provider, model: String, breakdown: TokenBreakdown)? {
        models.flatMap { p, mm in mm.map { (provider: p, model: $0.key, breakdown: $0.value) } }
            .max { $0.breakdown.total < $1.breakdown.total }
    }
}

/// An ascending series of `DayUsage` with day-key window helpers.
public struct UsageHistory: Sendable, Equatable {
    public let days: [DayUsage]

    public init(days: [DayUsage]) {
        self.days = days.sorted { $0.day < $1.day }
    }

    /// "yyyy-MM-dd" local-day key for a date, using the calendar's time zone.
    /// Built from date components (not DateFormatter) so locale can't change the format.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Sum of all days with startKey <= day <= endKey (inclusive), labelled endKey.
    public func rollup(from startKey: String, through endKey: String) -> DayUsage {
        DayUsage.sum(days.filter { $0.day >= startKey && $0.day <= endKey }, as: endKey)
    }
}
