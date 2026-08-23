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

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func setupNotificationCategories() {
        let cleanAction = UNNotificationAction(
            identifier: Self.cleanActionIdentifier,
            title: "Pulisci residui",
            options: [.foreground]
        )
        let ignoreAction = UNNotificationAction(
            identifier: Self.ignoreActionIdentifier,
            title: "Ignora",
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
        content.title = "\(event.displayName) spostata nel Cestino"
        let formattedSize = ByteCountFormatter.cleanerString(from: event.totalLeftoverBytes)
        content.body = "Trovati \(formattedSize) di file residui in Library. Vuoi esaminarli e spostarli nel Cestino?"
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

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even if app is in the foreground
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
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
