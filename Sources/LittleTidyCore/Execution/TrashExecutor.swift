import Foundation

public struct TrashExecutionResult: Sendable {
    public let trashed: [TrashedItem]
    public let failed: [(url: URL, error: Error)]
    public let skipped: [URL]

    public init(trashed: [TrashedItem], failed: [(url: URL, error: Error)], skipped: [URL]) {
        self.trashed = trashed
        self.failed = failed
        self.skipped = skipped
    }
}

public struct TrashedItem: Sendable, Equatable {
    public let sourceURL: URL
    public let trashURL: URL

    public init(sourceURL: URL, trashURL: URL) {
        self.sourceURL = sourceURL
        self.trashURL = trashURL
    }
}

public final class TrashExecutor: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func execute(_ plan: TrashPlan, deletionMode: DeletionMode = .moveToTrash) -> TrashExecutionResult {
        var trashed: [TrashedItem] = []
        var failed: [(url: URL, error: Error)] = []
        var skipped: [URL] = []

        for item in plan.items {
            guard fileManager.fileExists(atPath: item.sourceURL.path) else {
                skipped.append(item.sourceURL)
                continue
            }

            do {
                // Files of another user or locked files would stop a permanent
                // delete halfway; such items go to the Trash instead, which
                // the reported Trash URL makes visible.
                if deletionMode == .permanentDelete,
                   DeletionPreflight.obstacles(at: item.sourceURL).isEmpty {
                    try fileManager.removeItem(at: item.sourceURL)
                    trashed.append(TrashedItem(
                        sourceURL: item.sourceURL,
                        trashURL: item.sourceURL
                    ))
                } else {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: item.sourceURL, resultingItemURL: &resultingURL)
                    trashed.append(TrashedItem(
                        sourceURL: item.sourceURL,
                        trashURL: (resultingURL as URL?) ?? item.sourceURL
                    ))
                }
            } catch {
                failed.append((item.sourceURL, error))
            }
        }

        return TrashExecutionResult(trashed: trashed, failed: failed, skipped: skipped)
    }

    public func forceDelete(urls: [URL]) -> TrashExecutionResult {
        var deleted: [TrashedItem] = []
        var failed: [(url: URL, error: Error)] = []
        var skipped: [URL] = []

        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                skipped.append(url)
                continue
            }
            let obstacles = DeletionPreflight.obstacles(at: url)
            guard obstacles.isEmpty else {
                // Refuse up front rather than delete part of the item.
                failed.append((url, CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "\(url.lastPathComponent) was not deleted: \(obstacles.explanation), which only an administrator can delete."
                ])))
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                deleted.append(TrashedItem(sourceURL: url, trashURL: url))
            } catch {
                failed.append((url, error))
            }
        }

        return TrashExecutionResult(trashed: deleted, failed: failed, skipped: skipped)
    }
}
