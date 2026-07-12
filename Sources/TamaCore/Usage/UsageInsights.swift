import Foundation

/// Splits a TokenBreakdown into fresh (real work) vs cache-read vs cache-write, for the
/// cache-overhead proportion bar. Cost is computed separately (per model) in the UI.
public struct TokenComposition: Sendable, Equatable {
    public enum Part: Sendable { case fresh, cacheRead, cacheWrite }
    public let fresh: Int          // input + output
    public let cacheRead: Int
    public let cacheWrite: Int
    public var total: Int { fresh + cacheRead + cacheWrite }

    public init(_ b: TokenBreakdown) {
        self.fresh = b.input + b.output
        self.cacheRead = b.cacheRead
        self.cacheWrite = b.cacheWrite
    }

    /// Share of `total` for a part, 0…1. Returns 0 (never NaN) when total is 0.
    public func fraction(of part: Part) -> Double {
        guard total > 0 else { return 0 }
        let n: Int
        switch part {
        case .fresh: n = fresh
        case .cacheRead: n = cacheRead
        case .cacheWrite: n = cacheWrite
        }
        return Double(n) / Double(total)
    }
}

/// Direction + magnitude of a window's cost vs the prior equal-length window.
public enum UsageDelta: Sendable, Equatable {
    case up(Double)          // fractional increase, e.g. 0.12 = +12%
    case down(Double)        // fractional decrease
    case flat                // within ±0.5%
    case unavailable         // no prior data to compare against

    /// `flat` when |change| < 0.5%; `unavailable` when prior ≤ 0 (not enough history).
    public static func compare(current: Double, prior: Double) -> UsageDelta {
        guard prior > 0 else { return .unavailable }
        let change = (current - prior) / prior
        if abs(change) < 0.005 { return .flat }
        return change > 0 ? .up(change) : .down(-change)
    }
}
