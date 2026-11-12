import Foundation

/// Copies of attachments Mail saved when the person opened them. They can be
/// fetched again from the message, unless the person edited the copy.
public struct MailDownloadsAnalyzer: Sendable {
    private let folder: URL

    public init(
        folder: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true)
    ) {
        self.folder = folder
    }

    public func analyze() throws -> [EverydaySpaceItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw EverydayAccessError.needsAccess
        }

        var items: [EverydaySpaceItem] = []
        for url in children {
            try Task.checkCancellation()
            guard !FileSizing.isSymbolicLink(url) else { continue }
            let bytes = FileSizing.allocatedBytes(at: url)
            let edited = Self.mayContainEdits(url)
            items.append(EverydaySpaceItem(
                kind: .mailDownloads,
                name: Self.displayName(for: url),
                detail: edited ? "May contain your edits" : "Copy of an opened attachment",
                url: url,
                bytes: bytes,
                tier: edited ? .protected : .review,
                reason: edited
                    ? "A file here was changed after Mail saved it, so it may hold your own edits."
                    : "Mail saved this copy when you opened the attachment.",
                consequence: edited
                    ? "LittleTidy does not remove it."
                    : "Mail can fetch the attachment again from the message, as long as the message is still on the server or on this Mac."
            ))
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// A copy modified more than two seconds after it was created may have
    /// been edited by the person.
    static func mayContainEdits(_ url: URL) -> Bool {
        func edited(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let created = values.creationDate, let modified = values.contentModificationDate else { return false }
            return modified.timeIntervalSince(created) > 2
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if !isDirectory.boolValue { return edited(url) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]) else { return false }
        for case let file as URL in enumerator {
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            if edited(file) { return true }
        }
        return false
    }

    /// The folders are UUIDs; show the first file's name instead.
    static func displayName(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let first = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.filter({ !$0.hasPrefix(".") }).sorted().first
        else { return url.lastPathComponent }
        return first
    }
}
