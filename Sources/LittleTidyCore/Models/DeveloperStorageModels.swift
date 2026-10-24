import Foundation

public enum DeveloperStorageCategory: String, Codable, CaseIterable, Sendable {
    case simulatorDevices
    case simulatorRuntimes
    case xctestDevices
    case derivedData
    case deviceSupport
    case packageCaches
    case aiModelsAndAgents
    case aiCaches
    case aiGeneratedArtifacts
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
        case .aiModelsAndAgents: "AI Models"
        case .aiCaches: "AI Caches & Logs"
        case .aiGeneratedArtifacts: "AI Sessions & Artifacts"
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
    case homebrewCleanup
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
    /// Allocated bytes can overstate what removal frees right away: APFS clones
    /// share blocks, and a local snapshot (for example Time Machine's) keeps
    /// blocks that existed when it was taken. When measured, this is the APFS
    /// private size, a lower bound on the space freed immediately.
    public let minimumReclaimableBytes: Int64?

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
        isAvailable: Bool = true,
        minimumReclaimableBytes: Int64? = nil
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
        self.minimumReclaimableBytes = minimumReclaimableBytes.map { min($0, bytes) }
    }

    /// The bytes removal is guaranteed to free, falling back to allocated size.
    public var guaranteedReclaimableBytes: Int64 {
        minimumReclaimableBytes ?? bytes
    }

    /// Whether a meaningful part of this item is shared with clones or held
    /// by a local snapshot, so removal frees less right away.
    public var hasSharedStorage: Bool {
        guard let minimumReclaimableBytes else { return false }
        return bytes - minimumReclaimableBytes >= max(1_000_000, bytes / 10)
    }

    public func withMinimumReclaimableBytes(_ value: Int64?) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: id,
            category: category,
            name: name,
            detail: detail,
            url: url,
            bytes: bytes,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            activity: activity,
            recoverability: recoverability,
            cleanupMechanism: cleanupMechanism,
            consequence: consequence,
            recommendation: recommendation,
            recommendationReason: recommendationReason,
            externalIdentifier: externalIdentifier,
            isAvailable: isAvailable,
            minimumReclaimableBytes: value
        )
    }

    /// How a running Xcode affects cleanup of this item.
    public var xcodeActivityRule: XcodeActivityRule {
        if cleanupMechanism == .homebrewCleanup { return .independent }
        switch category {
        case .derivedData, .simulatorDevices, .xctestDevices:
            return .openFileCheck
        default:
            return .requiresXcodeQuit
        }
    }
}

extension SimulatorDeviceRecord {
    /// Anything but Shutdown (Booted, Booting, Creating, Shutting Down) means
    /// the device may be in use.
    public var isShutdown: Bool {
        state.localizedCaseInsensitiveCompare("Shutdown") == .orderedSame
    }
}

extension Collection where Element == SimulatorDeviceRecord {
    /// A test session is active when any clone of the testing set is not shut down.
    public var hasActiveTestSession: Bool {
        contains { !$0.isShutdown }
    }
}

public enum XcodeActivityRule: String, Codable, Sendable {
    /// Not owned by Xcode; cleanup never waits for it.
    case independent
    /// Allowed while Xcode runs only when no process has files open inside it.
    case openFileCheck
    /// Blocked whenever Xcode is running.
    case requiresXcodeQuit
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

    public func guaranteedReclaimableBytes(for recommendation: StorageRecommendation) -> Int64 {
        items.filter { $0.recommendation == recommendation }.reduce(0) { $0 + $1.guaranteedReclaimableBytes }
    }

    public func bytes(for category: DeveloperStorageCategory) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.bytes }
    }
}
