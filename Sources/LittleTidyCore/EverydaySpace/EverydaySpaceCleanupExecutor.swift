import Foundation

public protocol EverydayActivityChecking: Sendable {
    /// True when Mail runs, or when that cannot be checked.
    func isMailRunning() async -> Bool
    /// Paths open by any process of this user, or nil when the snapshot fails.
    func openFileSnapshot() async -> OpenFileSnapshot?
}

extension DeveloperToolActivityChecker: EverydayActivityChecking {}

/// Moves reviewed everyday-space items to the Trash, one by one, after the
/// same fail-closed checks the developer cleanup uses. Results use the
/// developer result type so the summary and Restore work unchanged.
///
/// Everything here goes to the Trash: the permanent-delete setting does not
/// apply to these personal files.
public actor EverydaySpaceCleanupExecutor {
    public typealias Trasher = @Sendable (URL) throws -> URL?

    private let allowedRoots: [URL]
    private let activity: any EverydayActivityChecking
    private let trash: Trasher

    public init(
        allowedRoots: [URL],
        activity: any EverydayActivityChecking = DeveloperToolActivityChecker(),
        trash: @escaping Trasher = EverydaySpaceCleanupExecutor.systemTrash
    ) {
        self.allowedRoots = allowedRoots
        self.activity = activity
        self.trash = trash
    }

    public static let systemTrash: Trasher = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    public func execute(items: [EverydaySpaceItem]) async -> DeveloperStorageCleanupResult {
        var results: [DeveloperStorageCleanupResultItem] = []
        for item in items {
            if Task.isCancelled { break }
            results.append(await run(item))
        }
        return DeveloperStorageCleanupResult(items: results)
    }

    private func run(_ item: EverydaySpaceItem) async -> DeveloperStorageCleanupResultItem {
        func skipped(_ message: String) -> DeveloperStorageCleanupResultItem {
            .init(itemID: item.id, name: item.name, bytes: item.bytes, status: .skipped, message: message)
        }

        guard item.isSelectable else { return skipped("LittleTidy does not remove this item.") }
        guard isInsideAllowedRoot(item.url) else { return skipped("It is outside the folders LittleTidy cleans, so it was left alone.") }
        guard !FileSizing.isSymbolicLink(item.url) else { return skipped("It is a symbolic link. LittleTidy never removes links.") }
        guard FileManager.default.fileExists(atPath: item.url.path) else { return skipped("It no longer exists.") }

        guard let snapshot = await activity.openFileSnapshot() else {
            return skipped("LittleTidy could not check for open files, so it cannot confirm nothing is using this. Nothing was removed.")
        }
        if snapshot.containsPath(within: item.url) {
            return skipped("An app has files open inside this item. Quit it and try again.")
        }
        if item.kind == .mailDownloads, await activity.isMailRunning() {
            return skipped("Quit Mail before cleaning its attachments. Nothing was removed.")
        }

        do {
            let destination = try trash(item.url)
            guard !FileManager.default.fileExists(atPath: item.url.path) else {
                return .init(itemID: item.id, name: item.name, bytes: item.bytes, status: .failed,
                             message: "It is still present after the move. Another process may have recreated it.")
            }
            return .init(
                itemID: item.id, name: item.name, bytes: item.bytes, status: .removed,
                message: "Moved to Trash. Empty the Trash to free this space.",
                movedToTrash: true, allocatedBytes: item.bytes,
                originalPath: item.url.path, trashPath: destination?.path
            )
        } catch {
            return .init(itemID: item.id, name: item.name, bytes: item.bytes, status: .failed,
                         message: "Could not move it to the Trash: \(error.localizedDescription)")
        }
    }

    /// The item's parent must resolve inside an allowed root, so a link in the
    /// path cannot lead out of it.
    private func isInsideAllowedRoot(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        return allowedRoots.contains { root in
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            return parent == resolved || parent.hasPrefix(resolved + "/")
        }
    }
}
