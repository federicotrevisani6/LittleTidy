import AppKit
import Foundation
import LittleTidyCore
import UserNotifications

@MainActor
final class AppUninstallNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppUninstallNotificationManager()

    nonisolated static let categoryIdentifier = "LITTLE_TIDY_APP_UNINSTALL"
    nonisolated static let cleanActionIdentifier = "CLEAN_LEFTOVERS_ACTION"
    nonisolated static let ignoreActionIdentifier = "IGNORE_ACTION"

    var onOpenLeftoverReview: ((String) -> Void)?

    private override init() {
        super.init()
        setupNotificationCategories()
    }

    func requestAuthorizationIfNeeded(completion: (@Sendable (Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            completion?(granted)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupNotificationCategories() {
        let cleanAction = UNNotificationAction(
            identifier: Self.cleanActionIdentifier,
            title: "Clean Leftovers",
            options: [.foreground]
        )
        let ignoreAction = UNNotificationAction(
            identifier: Self.ignoreActionIdentifier,
            title: "Ignore",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [cleanAction, ignoreAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func postNotification(for event: AppUninstallEvent) {
        guard event.totalLeftoverBytes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(event.displayName) moved to Trash"
        let formattedSize = ByteCountFormatter.cleanerString(from: event.totalLeftoverBytes)
        content.body = "Found \(formattedSize) of leftover files in ~/Library. Would you like to review and clean them?"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["bundleIdentifier": event.bundleIdentifier]

        let request = UNNotificationRequest(
            identifier: "uninstall-\(event.bundleIdentifier)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to post app uninstall notification: \(error.localizedDescription)")
            }
        }
    }

    func postTestNotification(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "LittleTidy"
        content.subtitle = "Notifications are working!"
        content.body = "You will be alerted when an application is moved to the Trash so you can clean associated leftover files."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["isTest": true]

        let request = UNNotificationRequest(
            identifier: "test-notification-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to post test notification: \(error.localizedDescription)")
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even if app is in the foreground
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["isTest"] as? Bool == true {
            completionHandler()
            return
        }

        guard let bundleID = userInfo["bundleIdentifier"] as? String else {
            completionHandler()
            return
        }

        if response.actionIdentifier == Self.cleanActionIdentifier ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                self.onOpenLeftoverReview?(bundleID)
            }
        }

        completionHandler()
    }
}
