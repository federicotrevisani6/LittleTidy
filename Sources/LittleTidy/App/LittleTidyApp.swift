import AppKit
import SwiftUI

@main
struct LittleTidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("LittleTidy", id: "main") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            SettingsView()
        }
    }
}

import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterManager = UpdaterManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = AppUninstallNotificationManager.shared
        updaterManager.start()
    }
}
