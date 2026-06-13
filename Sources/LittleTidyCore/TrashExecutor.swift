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

    public func execute(_ plan: TrashPlan) -> TrashExecutionResult {
        var trashed: [TrashedItem] = []
        var failed: [(url: URL, error: Error)] = []
        var skipped: [URL] = []

        for item in plan.items {
            guard fileManager.fileExists(atPath: item.sourceURL.path) else {
                skipped.append(item.sourceURL)
                continue
            }

            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: item.sourceURL, resultingItemURL: &resultingURL)
                trashed.append(TrashedItem(
                    sourceURL: item.sourceURL,
                    trashURL: (resultingURL as URL?) ?? item.sourceURL
                ))
            } catch {
                failed.append((item.sourceURL, error))
            }
        }

        return TrashExecutionResult(trashed: trashed, failed: failed, skipped: skipped)
    }
}
