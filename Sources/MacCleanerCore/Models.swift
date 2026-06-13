import Foundation

public enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum CleanupCategory: String, Codable, Sendable {
    case duplicate
    case largeFile
    case unusedApp
    case cache
}

public struct FileRecord: Hashable, Codable, Sendable {
    public let id: UUID
    public let url: URL
    public let fileSize: Int64
    public let allocatedSize: Int64?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let lastAccessDate: Date?
    public let contentType: String?
    public let isHidden: Bool
    public let volumeIdentifier: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        fileSize: Int64,
        allocatedSize: Int64? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        contentType: String? = nil,
        isHidden: Bool = false,
        volumeIdentifier: String? = nil
    ) {
        self.id = id
        self.url = url
        self.fileSize = fileSize
        self.allocatedSize = allocatedSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastAccessDate = lastAccessDate
        self.contentType = contentType
        self.isHidden = isHidden
        self.volumeIdentifier = volumeIdentifier
    }
}

public struct DuplicateGroup: Codable, Sendable {
    public let id: UUID
    public let contentHash: String
    public let files: [FileRecord]
    public let reclaimableBytes: Int64
    public let confidence: Confidence
    public let recommendedKeep: FileRecord?

    public init(
        id: UUID = UUID(),
        contentHash: String,
        files: [FileRecord],
        reclaimableBytes: Int64,
        confidence: Confidence,
        recommendedKeep: FileRecord?
    ) {
        self.id = id
        self.contentHash = contentHash
        self.files = files
        self.reclaimableBytes = reclaimableBytes
        self.confidence = confidence
        self.recommendedKeep = recommendedKeep
    }
}

public struct LargeFileCandidate: Codable, Sendable {
    public let file: FileRecord
    public let reason: String
    public let score: Int
    public let confidence: Confidence

    public init(file: FileRecord, reason: String, score: Int, confidence: Confidence) {
        self.file = file
        self.reason = reason
        self.score = score
        self.confidence = confidence
    }
}

/// A file or folder belonging to an app, located conservatively by exact
/// bundle identifier. Surfaced for "deep uninstall" and always Trash-only.
public struct RelatedAppData: Codable, Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let kind: String

    public init(url: URL, sizeBytes: Int64, kind: String) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.kind = kind
    }
}

public struct AppUsageRecord: Codable, Sendable {
    public let appURL: URL
    public let bundleIdentifier: String?
    public let displayName: String
    public let version: String?
    public let appSizeBytes: Int64
    public let lastOpenedDate: Date?
    public let installDate: Date?
    public let relatedDataEstimateBytes: Int64?
    public let relatedData: [RelatedAppData]
    public let confidence: Confidence

    public init(
        appURL: URL,
        bundleIdentifier: String?,
        displayName: String,
        version: String?,
        appSizeBytes: Int64,
        lastOpenedDate: Date?,
        installDate: Date?,
        relatedDataEstimateBytes: Int64?,
        relatedData: [RelatedAppData] = [],
        confidence: Confidence
    ) {
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.appSizeBytes = appSizeBytes
        self.lastOpenedDate = lastOpenedDate
        self.installDate = installDate
        self.relatedDataEstimateBytes = relatedDataEstimateBytes
        self.relatedData = relatedData
        self.confidence = confidence
    }
}

public struct TrashPlan: Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let items: [TrashPlanItem]
    public let totalBytes: Int64

    public init(id: UUID = UUID(), createdAt: Date = Date(), items: [TrashPlanItem]) {
        self.id = id
        self.createdAt = createdAt
        self.items = items
        self.totalBytes = items.reduce(0) { $0 + $1.bytes }
    }
}

public struct TrashPlanItem: Codable, Sendable {
    public let sourceURL: URL
    public let bytes: Int64
    public let category: CleanupCategory
    public let reason: String

    public init(sourceURL: URL, bytes: Int64, category: CleanupCategory, reason: String) {
        self.sourceURL = sourceURL
        self.bytes = bytes
        self.category = category
        self.reason = reason
    }
}
