import Foundation

/// Pure mapping from a scan to a `Mood`. No file I/O, no clock of its own — everything is
/// injected so it is fully unit-testable, matching the rest of `TamaCore`.
public struct MoodEngine {
    /// A session counts as "active" if its last activity is within this window of `now`.
    /// Defaults to `AgentMonitor.activeWindow` (900s) so the cat agrees with the rest of the UI.
    public let activeWindow: TimeInterval
    /// Above `activeWindow` but within this window → `.resting`; beyond it → `.napping`.
    public let restWindow: TimeInterval
    public let calendar: Calendar

    public init(activeWindow: TimeInterval = 900,
                restWindow: TimeInterval = 3600,
                calendar: Calendar = .current) {
        self.activeWindow = activeWindow
        self.restWindow = restWindow
        self.calendar = calendar
    }

    public func evaluate(activity: Activity, now: Date, state: CatState) -> (mood: Mood, state: CatState) {
        let mostRecent = activity.sessions.map(\.lastActivity).max()
        let activeCount = activity.sessions.filter {
            now.timeIntervalSince($0.lastActivity) < activeWindow
        }.count
        let hasActivityToday = mostRecent.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        // Greeting: a new local day AND there is activity to greet. Fires once — we stamp
        // lastSeenDay so the next scan falls through to working/resting.
        let isNewDay = state.lastSeenDay.map { !calendar.isDate($0, inSameDayAs: now) } ?? true
        if hasActivityToday && isNewDay {
            return (.greeting, CatState(lastSeenDay: now))
        }

        let mood: Mood
        if activeCount > 0 {
            mood = .working(intensity: activeCount)
        } else if let last = mostRecent, now.timeIntervalSince(last) < restWindow {
            mood = .resting
        } else {
            mood = .napping
        }

        // Keep lastSeenDay current whenever there's activity today, so greeting won't refire.
        let newState = hasActivityToday ? CatState(lastSeenDay: now) : state
        return (mood, newState)
    }
}
