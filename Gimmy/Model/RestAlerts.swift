import Foundation
import UserNotifications

/// Native stand-in for the old page's beep: a local notification when the rest target is reached,
/// so it also works with the phone locked.
enum RestAlerts {
    private static let id = "gimmy.rest"
    private static let delegate = ForegroundPresenter()

    static func configure() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(after seconds: Int, exercise: String) {
        let content = UNMutableNotificationContent()
        content.title = "Descanso cumprido"
        content.body = "Hora da próxima série de \(exercise)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }
}
