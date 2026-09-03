import Foundation

public enum DeveloperStorageCategory: String, Codable, CaseIterable, Sendable {
    case simulatorDevices
    case simulatorRuntimes
    case xctestDevices
    case derivedData
    case deviceSupport
    case packageCaches
    case aiModelsAndAgents
    case archives
    case androidEmulators
    case testArtifacts
    case otherDeveloperData

    public var displayName: String {
        switch self {
        case .simulatorDevices: "Simulator Devices"
        case .simulatorRuntimes: "Simulator Runtimes"
        case .xctestDevices: "XCTest Devices"
        case .derivedData: "Derived Data"
        case .deviceSupport: "Device Support"
        case .packageCaches: "Package Manager Caches"
        case .aiModelsAndAgents: "AI Agents & Models"
        case .archives: "Archives & Symbols"
        case .androidEmulators: "Android Emulators"
        case .testArtifacts: "Test Results"
        case .otherDeveloperData: "Other Developer Data"
        }
    }
}
public enum StorageRecommendation: String, Codable, CaseIterable, Sendable {
    case recommended
    case review
    case protected
    case unclassified
}

public enum StorageRecoverability: String, Codable, Sendable {
    case trashRestorable
    case recreatable
    case reinstallable
    case irreversible
    case unknown
}

public enum StorageActivityState: String, Codable, Sendable {
    case active
    case recentlyUsed
    case inactive
    case unavailable
    case unknown
}

public enum DeveloperCleanupMechanism: String, Codable, Sendable {
    case trash
    case simctl
    case xcodeManaged
    case manual
    case unsupported
}

public enum CleanupConsequence: String, Codable, Sendable {
    case negligible
    case temporarySlowdown
    case redownloadRequired
    case debuggingImpact
    case dataLossRisk
    case unknown
}

public struct DeveloperStorageItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let category: DeveloperStorageCategory
    public let name: String
    public let detail: String
    public let url: URL?
    public let bytes: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let activity: StorageActivityState
    public let recoverability: StorageRecoverability
    public let cleanupMechanism: DeveloperCleanupMechanism
    public let consequence: CleanupConsequence
    public let recommendation: StorageRecommendation
    public let recommendationReason: String
    public let externalIdentifier: String?
    public let isAvailable: Bool

    public init(
        id: String,
        category: DeveloperStorageCategory,
        name: String,
        detail: String,
        url: URL?,
        bytes: Int64,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        activity: StorageActivityState,
        recoverability: StorageRecoverability,
        cleanupMechanism: DeveloperCleanupMechanism,
        consequence: CleanupConsequence,
        recommendation: StorageRecommendation,
        recommendationReason: String,
        externalIdentifier: String? = nil,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.detail = detail
        self.url = url
        self.bytes = bytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.activity = activity
        self.recoverability = recoverability
        self.cleanupMechanism = cleanupMechanism
        self.consequence = consequence
        self.recommendation = recommendation
        self.recommendationReason = recommendationReason
        self.externalIdentifier = externalIdentifier
        self.isAvailable = isAvailable
    }
}

public struct DeveloperStorageAccessIssue: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.id = path
        self.path = path
        self.message = message
    }
}

public struct DeveloperStorageInventory: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let items: [DeveloperStorageItem]
    public let accessIssues: [DeveloperStorageAccessIssue]
    public let simulatorToolAvailable: Bool

    public init(
        scannedAt: Date = Date(),
        items: [DeveloperStorageItem],
        accessIssues: [DeveloperStorageAccessIssue] = [],
        simulatorToolAvailable: Bool
    ) {
        self.scannedAt = scannedAt
        self.items = items
        self.accessIssues = accessIssues
        self.simulatorToolAvailable = simulatorToolAvailable
    }

    public static let empty = DeveloperStorageInventory(
        scannedAt: .distantPast,
        items: [],
        accessIssues: [],
        simulatorToolAvailable: false
    )

    public func bytes(for recommendation: StorageRecommendation) -> Int64 {
        items.filter { $0.recommendation == recommendation }.reduce(0) { $0 + $1.bytes }
    }

    public func bytes(for category: DeveloperStorageCategory) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.bytes }
    }
}
