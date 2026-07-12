import Foundation
import UserNotifications
import TamaCore

/// Thin `UNUserNotificationCenter` wrapper. UserNotifications requires a real app bundle —
/// a bare `swift run` binary has none, and calling into it would misbehave — so every call
/// is gated on `Bundle.main.bundleIdentifier`. Permission is requested only from the
/// Settings toggle (first opt-in), never at launch.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ events: [NotificationEvent]) {
        guard available, !events.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for e in events {
            let content = UNMutableNotificationContent()
            content.title = e.title
            content.body = e.body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
    }
}
