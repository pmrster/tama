import Foundation

/// A user-facing alert derived from session state. Pure value; the shell decides whether
/// and how to post it (UserNotifications), gated by the user's settings toggles.
public struct NotificationEvent: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case agentQuiet, contextHigh }
    public let kind: Kind
    public let sessionID: String
    public let title: String
    public let body: String
    public init(kind: Kind, sessionID: String, title: String, body: String) {
        self.kind = kind; self.sessionID = sessionID; self.title = title; self.body = body
    }
}

/// Pure notification logic, driven by successive `evaluate` calls after each poll.
/// No AppKit, no clock access beyond the `now` parameter — unit-tested with a fake clock.
///
/// agentQuiet: fires ONCE when a session that was OBSERVED streaming (seen with
/// quiet < threshold) goes silent for ≥ `quietThreshold` while still inside
/// `activeWindow`; re-arms when the session writes again. Sessions first seen already
/// quiet (app launch) or aged past the active window never fire.
///
/// contextHigh: fires ONCE when `contextFraction` reaches `contextThreshold`; re-arms
/// only after it drops below `rearmBelow` (post-compaction hysteresis).
public struct NotificationPolicy: Sendable {
    public var quietThreshold: TimeInterval = 180
    public var activeWindow: TimeInterval = 900     // mirrors AgentMonitor.activeWindow
    public var contextThreshold: Double = 0.85
    public var rearmBelow: Double = 0.75

    private struct SessionState {
        var lastActivity: Date
        var observedStreaming = false
        var quietFired = false
        var contextFired = false
    }
    private var states: [String: SessionState] = [:]

    public init() {}

    public mutating func evaluate(sessions: [SessionInfo], now: Date) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        var next: [String: SessionState] = [:]
        for s in sessions {
            var st = states[s.id] ?? SessionState(lastActivity: s.lastActivity)
            if s.lastActivity != st.lastActivity {          // new write → re-arm quiet rule
                st.lastActivity = s.lastActivity
                st.observedStreaming = false
                st.quietFired = false
            }
            let quiet = now.timeIntervalSince(s.lastActivity)
            if quiet < quietThreshold { st.observedStreaming = true }
            if st.observedStreaming, !st.quietFired, quiet >= quietThreshold, quiet < activeWindow {
                st.quietFired = true
                events.append(NotificationEvent(
                    kind: .agentQuiet, sessionID: s.id,
                    title: "Agent may be waiting",
                    body: "\(s.project) · \(s.displayName): no activity for \(Int(quiet / 60)) min"))
            }
            if let f = s.contextFraction {
                if f >= contextThreshold, !st.contextFired {
                    st.contextFired = true
                    events.append(NotificationEvent(
                        kind: .contextHigh, sessionID: s.id,
                        title: "Context nearly full",
                        body: "\(s.project) · \(s.displayName): context window \(Int(f * 100))% full"))
                } else if f < rearmBelow {
                    st.contextFired = false
                }
            }
            next[s.id] = st
        }
        states = next   // sessions no longer listed drop their state
        return events
    }
}
