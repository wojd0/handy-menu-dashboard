import Foundation
import UserNotifications

@MainActor
protocol SessionUpdateNotifying: AnyObject {
    var onOpen: (() -> Void)? { get set }
    func notify(pending: [Provider]) async
    func clear() async
}

@MainActor
final class UserNotificationsNotifier: NSObject, SessionUpdateNotifying, UNUserNotificationCenterDelegate {
    static let requestIdentifier = "com.wojd0.dashboard.sessionUpdate"

    var onOpen: (() -> Void)?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func notify(pending: [Provider]) async {
        guard !pending.isEmpty, await ensureAuthorization() else { return }

        let names = pending.map(\.displayName).joined(separator: ", ")
        let content = UNMutableNotificationContent()
        content.title = pending.count == 1 ? "\(names) needs updating" : "\(pending.count) agents need updating"
        content.body = "Approve to refresh \(pending.count == 1 ? "this session" : "these sessions") from your browser."
        content.sound = nil

        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    func clear() async {
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            onOpen?()
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }
}

@MainActor
final class DisabledNotifier: SessionUpdateNotifying {
    var onOpen: (() -> Void)?
    func notify(pending: [Provider]) async {}
    func clear() async {}
}
