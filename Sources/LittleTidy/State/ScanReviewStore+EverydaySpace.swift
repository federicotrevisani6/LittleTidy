import AppKit
import Foundation
import LittleTidyCore

extension ScanReviewStore {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var downloadsURL: URL { home.appendingPathComponent("Downloads", isDirectory: true) }
    private static var backupsURL: URL { home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true) }
    private static var mailDownloadsURL: URL { home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true) }

    /// Downloads is read only when the person approved it, directly or through
    /// a parent folder they approved.
    var isDownloadsApproved: Bool {
        let downloads = Self.downloadsURL.standardizedFileURL.path
        return scanRoots.contains { root in
            let path = root.standardizedFileURL.path
            return downloads == path || downloads.hasPrefix(path + "/")
        }
    }

    func scanEverydaySpace() {
        guard !isScanningEveryday else { return }
        isScanningEveryday = true
        let downloadsApproved = isDownloadsApproved
        let appRoots = self.appRoots
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task { [weak self] in
            let scanned = await Task.detached(priority: .utility) { () -> [EverydayScanResult] in
                func run(_ kind: EverydaySpaceKind, _ analyze: () throws -> [EverydaySpaceItem]) -> EverydayScanResult {
                    do {
                        return EverydayScanResult(kind: kind, items: try analyze())
                    } catch EverydayAccessError.needsAccess {
                        return EverydayScanResult(kind: kind, items: [], problem: .needsAccess)
                    } catch {
                        return EverydayScanResult(kind: kind, items: [])
                    }
                }
                var found: [EverydayScanResult] = []
                if downloadsApproved {
                    found.append(run(.installers) { try DownloadsClutterAnalyzer().analyze() })
                } else {
                    found.append(EverydayScanResult(kind: .installers, items: [], problem: .folderNotApproved))
                }
                found.append(run(.iosBackups) { try IOSBackupAnalyzer().analyze() })
                found.append(run(.mailDownloads) { try MailDownloadsAnalyzer().analyze() })
                return found
            }.value
            var results = scanned
            if let leftovers = try? await OrphanLeftoverAnalyzer(appRoots: appRoots, runningBundleIDs: { running }).analyze() {
                results.append(leftovers)
            }
            guard let self else { return }
            self.everydayResults = Dictionary(uniqueKeysWithValues: results.map { ($0.kind, $0) })
            self.isScanningEveryday = false
        }
    }

    // MARK: - Review

    func everydayItems(_ kind: EverydaySpaceKind) -> [EverydaySpaceItem] {
        everydayResults[kind]?.items ?? []
    }

    func reviewEveryday(_ kind: EverydaySpaceKind) {
        everydaySelection = []
        cleanAllSummary = nil
        restoreResult = nil
        everydayReviewKind = kind
    }

    func dismissEverydayReview() {
        everydayReviewKind = nil
        everydaySelection = []
        cleanAllSummary = nil
        restoreResult = nil
    }

    func toggleEverydaySelection(_ item: EverydaySpaceItem) {
        guard item.isSelectable, !isCleaningDeveloperStorage else { return }
        if everydaySelection.contains(item.id) { everydaySelection.remove(item.id) } else { everydaySelection.insert(item.id) }
    }

    func selectedEverydayItems(_ kind: EverydaySpaceKind) -> [EverydaySpaceItem] {
        everydayItems(kind).filter { everydaySelection.contains($0.id) && $0.isSelectable }
    }

    // MARK: - Move to the Trash

    /// Moves the picked items to the Trash after the executor's own checks.
    /// Nothing is permanent: the Trash keeps everything until it is emptied.
    func moveEverydaySelectionToTrash(_ kind: EverydaySpaceKind) {
        let items = selectedEverydayItems(kind)
        guard !items.isEmpty, !isCleaningDeveloperStorage else { return }
        isCleaningDeveloperStorage = true
        let library = Self.home.appendingPathComponent("Library", isDirectory: true)
        let roots = [Self.downloadsURL, Self.backupsURL, Self.mailDownloadsURL]
            + OrphanLeftoverAnalyzer.libraryFolders.map { library.appendingPathComponent($0, isDirectory: true) }
        let card = kind.cardID
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task { [weak self] in
            let result = await EverydaySpaceCleanupExecutor(allowedRoots: roots, runningBundleIDs: { running }).execute(items: items)
            guard let self else { return }
            let summary = CleanupSummary.make(from: result) { _ in card }
            self.cleanAllSummary = summary
            self.restoreResult = nil
            self.lastCleanupTrashPaths = Set(summary.restorable.map { $0.trashURL.path })
            self.recordCleanAllHistory(result: result, summary: summary)
            self.everydaySelection = []
            self.isCleaningDeveloperStorage = false
            self.refreshTrashPreview()
            self.scanEverydaySpace()
        }
    }
}
