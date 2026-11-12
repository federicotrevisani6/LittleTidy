import Darwin
import Foundation

public struct RestorableItem: Equatable, Sendable, Identifiable {
    public var id: String { trashURL.path }
    public let name: String
    public let originalURL: URL
    public let trashURL: URL

    public init(name: String, originalURL: URL, trashURL: URL) {
        self.name = name
        self.originalURL = originalURL
        self.trashURL = trashURL
    }
}

public struct TrashRestoreResult: Equatable, Sendable {
    public struct Issue: Equatable, Sendable {
        public let name: String
        public let reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public let restored: [RestorableItem]
    /// Items left in the Trash, each with the reason: no longer there, the
    /// original place is taken, its folder is gone, or the move failed.
    public let notRestored: [Issue]

    public init(restored: [RestorableItem], notRestored: [Issue]) {
        self.restored = restored
        self.notRestored = notRestored
    }
}

/// Puts items LittleTidy moved to the Trash back where they were. It never
/// overwrites, never recreates a missing folder, and only touches items that
/// are still inside a Trash folder.
public struct TrashRestorer: Sendable {
    public init() {}

    public func restore(_ items: [RestorableItem]) -> TrashRestoreResult {
        var restored: [RestorableItem] = []
        var issues: [TrashRestoreResult.Issue] = []

        for item in items {
            if let reason = blockingReason(for: item) {
                issues.append(.init(name: item.name, reason: reason))
                continue
            }
            do {
                // moveItem renames the item itself; a symlink moves as a link.
                try FileManager.default.moveItem(at: item.trashURL, to: item.originalURL)
                restored.append(item)
            } catch {
                issues.append(.init(name: item.name, reason: "The move failed: \(error.localizedDescription)"))
            }
        }
        return TrashRestoreResult(restored: restored, notRestored: issues)
    }

    private func blockingReason(for item: RestorableItem) -> String? {
        guard Self.isInsideTrash(item.trashURL), !Self.isInsideTrash(item.originalURL) else {
            return "It is not inside a Trash folder, so LittleTidy leaves it alone."
        }
        guard Self.exists(item.trashURL) else {
            return "It is no longer in the Trash."
        }
        guard !Self.exists(item.originalURL) else {
            return "Something already exists at its original place. It stays in the Trash."
        }
        var isDirectory: ObjCBool = false
        let parent = item.originalURL.deletingLastPathComponent().path
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Its original folder no longer exists."
        }
        return nil
    }

    /// lstat, so a symlink counts as present and is never followed.
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func isInsideTrash(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        return components.contains(".Trash") || components.contains(".Trashes")
    }
}
