import Foundation

/// The everyday space LittleTidy looks for beyond developer data: installers
/// and archives in Downloads, iOS device backups and Mail's opened attachments.
public enum EverydaySpaceKind: String, CaseIterable, Identifiable, Sendable {
    case installers
    case iosBackups
    case mailDownloads
    case appLeftovers

    public var id: String { rawValue }

    public var cardID: SmartCareCardID {
        switch self {
        case .installers: .installers
        case .iosBackups: .iosBackups
        case .mailDownloads: .mailAttachments
        case .appLeftovers: .leftovers
        }
    }
}

public struct EverydaySpaceItem: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let kind: EverydaySpaceKind
    public let name: String
    /// One line under the name: size context, age, device and version.
    public let detail: String
    public let url: URL
    public let bytes: Int64
    /// `review` for something a person decides on; `protected` when it may
    /// hold edits; `unclassified` when it cannot be recognised. Never
    /// `recommended`: these are the user's own files.
    public let tier: StorageRecommendation
    public let reason: String
    public let consequence: String
    /// A stronger warning applies, for example the newest backup of a device.
    public let warning: String?
    /// The app identifier a leftover belongs to, so a running app can be noticed.
    public let bundleID: String?

    public init(
        kind: EverydaySpaceKind,
        name: String,
        detail: String,
        url: URL,
        bytes: Int64,
        tier: StorageRecommendation,
        reason: String,
        consequence: String,
        warning: String? = nil,
        bundleID: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.url = url
        self.bytes = bytes
        self.tier = tier
        self.reason = reason
        self.consequence = consequence
        self.warning = warning
        self.bundleID = bundleID
    }

    /// Only review items can be picked: protected and unclassified ones are
    /// shown for awareness and never removed.
    public var isSelectable: Bool { tier == .review }
}

/// What one analyzer found, or why it could not look.
public struct EverydayScanResult: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// macOS refused to read the folder: Full Disk Access is missing.
        case needsAccess
        /// Downloads is not one of the folders the person approved.
        case folderNotApproved
        /// The check that proves an app is gone could not run, so nothing is listed.
        case cannotVerify
    }

    public let kind: EverydaySpaceKind
    public let items: [EverydaySpaceItem]
    public let problem: Problem?

    public init(kind: EverydaySpaceKind, items: [EverydaySpaceItem], problem: Problem? = nil) {
        self.kind = kind
        self.items = items
        self.problem = problem
    }
}

public enum EverydayAccessError: Error, Equatable, Sendable {
    case needsAccess
}

/// Allocated size of a file or folder without following links.
public enum FileSizing {
    public static func allocatedBytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        func size(_ url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        func isLink(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        }
        if isLink(url) { return 0 }
        var total = size(url)
        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey],
            options: []
        ) {
            for case let child as URL in enumerator where !isLink(child) {
                total += size(child)
            }
        }
        return total
    }

    public static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
