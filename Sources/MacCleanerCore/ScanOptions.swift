import Foundation

public struct ScanRequest: Sendable {
    public let roots: [URL]
    public let options: ScanOptions

    public init(roots: [URL], options: ScanOptions = ScanOptions()) {
        self.roots = roots
        self.options = options
    }
}

public struct ScanOptions: Sendable {
    public var includeHiddenFiles: Bool
    public var includeSystemFolders: Bool
    public var followSymbolicLinks: Bool
    public var minimumDuplicateSize: Int64
    public var largeFileThreshold: Int64

    public init(
        includeHiddenFiles: Bool = false,
        includeSystemFolders: Bool = false,
        followSymbolicLinks: Bool = false,
        minimumDuplicateSize: Int64 = 1_000_000,
        largeFileThreshold: Int64 = 500_000_000
    ) {
        self.includeHiddenFiles = includeHiddenFiles
        self.includeSystemFolders = includeSystemFolders
        self.followSymbolicLinks = followSymbolicLinks
        self.minimumDuplicateSize = minimumDuplicateSize
        self.largeFileThreshold = largeFileThreshold
    }
}

public enum ScanEvent: Sendable {
    case started(rootCount: Int)
    case rootStarted(url: URL, index: Int, total: Int)
    case indexedFile(FileRecord)
    case skipped(URL, reason: String)
    case permissionDenied(URL, Error)
    case progress(ScanProgress)
    case completed(ScanSummary)
}

public struct ScanProgress: Sendable {
    public let currentRoot: URL?
    public let rootIndex: Int
    public let rootCount: Int
    public let scannedFiles: Int
    public let scannedBytes: Int64
    public let skippedItems: Int
    public let permissionErrors: Int

    public init(
        currentRoot: URL?,
        rootIndex: Int,
        rootCount: Int,
        scannedFiles: Int,
        scannedBytes: Int64,
        skippedItems: Int,
        permissionErrors: Int
    ) {
        self.currentRoot = currentRoot
        self.rootIndex = rootIndex
        self.rootCount = rootCount
        self.scannedFiles = scannedFiles
        self.scannedBytes = scannedBytes
        self.skippedItems = skippedItems
        self.permissionErrors = permissionErrors
    }
}

public struct ScanSummary: Sendable {
    public let scannedFiles: Int
    public let scannedBytes: Int64
    public let skippedItems: Int
    public let permissionErrors: Int

    public init(scannedFiles: Int, scannedBytes: Int64, skippedItems: Int, permissionErrors: Int) {
        self.scannedFiles = scannedFiles
        self.scannedBytes = scannedBytes
        self.skippedItems = skippedItems
        self.permissionErrors = permissionErrors
    }
}
