import AppKit
import LittleTidyCore

extension FullDiskAccess {
    @MainActor
    public static func openPrivacySettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
