import Foundation

/// Posts a desktop notification. Abstracted so the app can inject a real
/// `UNUserNotificationCenter`-backed implementation (and tests, a fake).
public protocol Notifier: Sendable {
    func post(_ notification: AppNotification, sound: Bool)
}
