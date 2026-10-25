import Darwin
import Foundation

/// Files a permanent delete cannot remove without administrator rights: owned
/// by another user (for example root, or a removed account) or locked with an
/// immutable flag. Found before deleting, so a delete never stops halfway.
public struct DeletionObstacles: Equatable, Sendable {
    public let foreignOwnedCount: Int
    public let lockedCount: Int
    /// Owner names, or "UID n" for accounts that no longer exist.
    public let owners: [String]

    public init(foreignOwnedCount: Int = 0, lockedCount: Int = 0, owners: [String] = []) {
        self.foreignOwnedCount = foreignOwnedCount
        self.lockedCount = lockedCount
        self.owners = owners
    }

    public var isEmpty: Bool { foreignOwnedCount == 0 && lockedCount == 0 }

    public var explanation: String {
        var parts: [String] = []
        if foreignOwnedCount > 0 {
            parts.append("\(foreignOwnedCount) files belong to \(owners.isEmpty ? "another user" : owners.joined(separator: ", "))")
        }
        if lockedCount > 0 {
            parts.append("\(lockedCount) files are locked")
        }
        return parts.joined(separator: " and ")
    }

    public static let none = DeletionObstacles()
}

public enum DeletionPreflight {
    /// Walks the tree with lstat, never following links. Moving a folder to
    /// the Trash still works when it contains such files, because only the
    /// top folder is renamed.
    public static func obstacles(at url: URL, userID: uid_t = getuid()) -> DeletionObstacles {
        var foreign = 0
        var locked = 0
        var ownerIDs: Set<uid_t> = []

        func inspect(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else { return }
            if info.st_uid != userID {
                foreign += 1
                ownerIDs.insert(info.st_uid)
            }
            if info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE) != 0 {
                locked += 1
            }
        }

        inspect(url.path)
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            for case let relative as String in enumerator {
                inspect(url.appendingPathComponent(relative).path)
            }
        }

        let owners = ownerIDs.sorted().map { uid -> String in
            if let entry = getpwuid(uid), let name = String(validatingCString: entry.pointee.pw_name) {
                return name
            }
            return "UID \(uid), an account that no longer exists"
        }
        return DeletionObstacles(foreignOwnedCount: foreign, lockedCount: locked, owners: owners)
    }
}
