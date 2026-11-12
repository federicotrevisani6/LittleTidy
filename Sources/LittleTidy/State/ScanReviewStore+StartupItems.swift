import Foundation
import LittleTidyCore

extension ScanReviewStore {
    func scanStartupItems() {
        guard !isScanningStartupItems else { return }
        isScanningStartupItems = true
        Task { [weak self] in
            let result = await StartupItemAnalyzer().analyze()
            guard let self else { return }
            self.startupItems = result.items
            self.startupAccessIssues = result.accessIssues
            self.isScanningStartupItems = false
        }
    }

    /// Switches a login item on or off. The controller re-reads the item right
    /// before acting and refuses anything that changed since the scan.
    func setStartsAtLogin(_ enabled: Bool, item: StartupItem) {
        guard changingStartupItemID == nil else { return }
        changingStartupItemID = item.id
        startupMessage = nil
        Task { [weak self] in
            let analyzer = StartupItemAnalyzer()
            let controller = StartupItemController(reload: { await analyzer.analyze().items })
            var message: String
            do {
                message = "\(item.displayName): " + (try await controller.setStartsAtLogin(enabled, item: item))
            } catch {
                message = "\(item.displayName): \(error.localizedDescription)"
            }
            guard let self else { return }
            self.startupMessage = message
            self.changingStartupItemID = nil
            self.isScanningStartupItems = false
            self.scanStartupItems()
        }
    }
}
