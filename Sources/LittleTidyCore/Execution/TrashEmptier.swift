import Darwin
import Foundation

public struct TrashEmptyItem: Equatable, Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    /// Moved here by LittleTidy in its last cleanup: the user's only undo.
    public let isFromLastCleanup: Bool

    public init(url: URL, bytes: Int64, isFromLastCleanup: Bool) {
        self.url = url
        self.bytes = bytes
        self.isFromLastCleanup = isFromLastCleanup
    }
}

public struct TrashEmptyPreview: Equatable, Sendable {
    /// Items from the last cleanup first, then largest first.
    public let items: [TrashEmptyItem]
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var fromLastCleanupCount: Int { items.filter(\.isFromLastCleanup).count }

    public init(items: [TrashEmptyItem]) { self.items = items }
}

public struct TrashEmptyResult: Sendable {
    public struct Skipped: Sendable, Equatable {
        public let url: URL
        public let reason: String
    }

    public let removed: [URL]
    public let skipped: [Skipped]
    public let failed: [Skipped]
    public let bytesRemoved: Int64
    /// Set when nothing was attempted because a safety check could not run.
    public let blockedReason: String?

    public init(removed: [URL], skipped: [Skipped], failed: [Skipped], bytesRemoved: Int64, blockedReason: String? = nil) {
        self.removed = removed
        self.skipped = skipped
        self.failed = failed
        self.bytesRemoved = bytesRemoved
        self.blockedReason = blockedReason
    }
}

/// Empties the user's own Trash. This is the single place where LittleTidy
/// removes files permanently, so it is deliberately narrow:
/// - only direct children of one Trash folder, never external volumes;
/// - symlinks are removed as links and never followed;
/// - a missing open-file snapshot blocks everything;
/// - files in use, owned by someone else or locked are skipped, never forced;
/// - no shell, no elevation.
public struct TrashEmptier: Sendable {
    public typealias SnapshotProvider = @Sendable () async -> OpenFileSnapshot?

    private let trashURL: URL
    private let snapshotProvider: SnapshotProvider
    private let userID: uid_t

    public init(
        trashURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true),
        userID: uid_t = getuid(),
        snapshotProvider: @escaping SnapshotProvider
    ) {
        self.trashURL = trashURL
        self.userID = userID
        self.snapshotProvider = snapshotProvider
    }

    /// Lists what Empty would remove. Throws when the Trash cannot be read,
    /// for example without Full Disk Access; that is "needs access", not empty.
    public func preview(lastCleanupPaths: Set<String> = []) throws -> TrashEmptyPreview {
        let children = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        let normalizedLast = Set(lastCleanupPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let items = children.map { child in
            TrashEmptyItem(
                url: child,
                bytes: Self.allocatedBytes(at: child),
                isFromLastCleanup: normalizedLast.contains(child.standardizedFileURL.path)
            )
        }
        .sorted {
            if $0.isFromLastCleanup != $1.isFromLastCleanup { return $0.isFromLastCleanup }
            return $0.bytes > $1.bytes
        }
        return TrashEmptyPreview(items: items)
    }

    public func empty() async -> TrashEmptyResult {
        guard let snapshot = await snapshotProvider() else {
            return TrashEmptyResult(
                removed: [], skipped: [], failed: [], bytesRemoved: 0,
                blockedReason: "LittleTidy could not check for open files, so it cannot confirm nothing is using the Trash. Nothing was removed."
            )
        }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [])
        } catch {
            return TrashEmptyResult(
                removed: [], skipped: [], failed: [], bytesRemoved: 0,
                blockedReason: "LittleTidy cannot read the Trash. Allow Full Disk Access and try again. Nothing was removed."
            )
        }

        var removed: [URL] = []
        var skipped: [TrashEmptyResult.Skipped] = []
        var failed: [TrashEmptyResult.Skipped] = []
        var bytes: Int64 = 0

        for child in children {
            if Task.isCancelled { break }
            if Self.isSymlink(child) {
                // Removing the link itself never touches its target.
                do {
                    try FileManager.default.removeItem(at: child)
                    removed.append(child)
                } catch {
                    failed.append(.init(url: child, reason: error.localizedDescription))
                }
                continue
            }
            if snapshot.containsPath(within: child) {
                skipped.append(.init(url: child, reason: "An app has files open inside this item."))
                continue
            }
            let obstacles = DeletionPreflight.obstacles(at: child, userID: userID)
            if !obstacles.isEmpty {
                skipped.append(.init(url: child, reason: "Needs administrator rights: \(obstacles.explanation)."))
                continue
            }
            let size = Self.allocatedBytes(at: child)
            do {
                try FileManager.default.removeItem(at: child)
                removed.append(child)
                bytes += size
            } catch {
                failed.append(.init(url: child, reason: error.localizedDescription))
            }
        }

        return TrashEmptyResult(removed: removed, skipped: skipped, failed: failed, bytesRemoved: bytes)
    }

    static func isSymlink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    /// Allocated size without following links.
    static func allocatedBytes(at url: URL) -> Int64 {
        func size(of url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        if isSymlink(url) { return 0 }
        var total = size(of: url)
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: []) {
            for case let child as URL in enumerator where !isSymlink(child) {
                total += size(of: child)
            }
        }
        return total
    }
}
