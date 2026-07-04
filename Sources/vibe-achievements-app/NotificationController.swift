import Foundation
import UserNotifications

enum NotificationController {
    static func requestAuthorization(completion: (@Sendable () -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            completion?()
        }
    }

    static func notify(unlockName: String, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked"
        content.body = "\(unlockName): \(summary)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
