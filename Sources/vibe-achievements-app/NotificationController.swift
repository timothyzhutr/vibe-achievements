import Foundation
import UserNotifications

enum NotificationController {
    /// UNUserNotificationCenter requires a real app bundle; calling it from a
    /// bare executable (e.g. `swift run`) raises an Objective-C exception.
    static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthorization(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard notificationsAvailable else {
            // No notification support in this context, but the caller still
            // needs its continuation (it kicks off the initial scan).
            completion?(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion?(granted)
        }
    }

    static func notify(unlockName: String, summary: String) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked"
        content.body = "\(unlockName): \(summary)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
