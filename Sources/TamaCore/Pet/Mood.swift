import Foundation

/// The companion cat's current feeling, derived from live activity. Positive-only:
/// there is no sad/sick/dying state and no needs-decay clock (see the Phase 1 spec).
public enum Mood: Sendable, Equatable {
    /// Transient: the first activity of a new local day.
    case greeting
    /// A session is active right now. `intensity` = count of currently-active sessions.
    case working(intensity: Int)
    /// Recent activity, but paused.
    case resting
    /// Idle / away / no activity today.
    case napping
}

/// The cat's own persisted state (NOT agent data). Phase 1 stores only the last day the
/// cat "saw" activity, which gates the once-per-day greeting.
public struct CatState: Sendable, Equatable, Codable {
    public var lastSeenDay: Date?
    public init(lastSeenDay: Date? = nil) { self.lastSeenDay = lastSeenDay }
    public static let initial = CatState()
}
