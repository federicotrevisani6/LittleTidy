import Foundation

public enum SmartCareGroup: String, CaseIterable, Identifiable, Sendable {
    case cleanup, apps, maintenance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cleanup: "Cleanup"
        case .apps: "Applications"
        case .maintenance: "Maintenance"
        }
    }
}

/// Cards in precedence order: when two cards could claim the same path, the
/// card that comes first owns it (spec section 6).
public enum SmartCareCardID: String, CaseIterable, Identifiable, Sendable {
    case developer
    case aiTools
    case caches
    case trash
    case unusedApps
    case snapshots
    case startupItems

    public var id: String { rawValue }

    public var group: SmartCareGroup {
        switch self {
        case .developer, .aiTools, .caches, .trash: .cleanup
        case .unusedApps: .apps
        case .snapshots, .startupItems: .maintenance
        }
    }

    public var title: String {
        switch self {
        case .developer: "Developer storage"
        case .aiTools: "AI tools"
        case .caches: "System and app caches"
        case .trash: "Trash"
        case .unusedApps: "Unused applications"
        case .snapshots: "Time Machine snapshots"
        case .startupItems: "Login and background items"
        }
    }

    public var explanation: String {
        switch self {
        case .developer: "Simulators, build data, device support files and package caches."
        case .aiTools: "Caches, logs, session data and local models of AI tools."
        case .caches: "Files apps and macOS can rebuild. Apps may start a little slower once."
        case .trash: "Items you already moved to the Trash. Emptying it cannot be undone."
        case .unusedApps: "Apps you have not opened for a long time."
        case .snapshots: "Local Time Machine copies macOS can release when space is needed."
        case .startupItems: "Apps and helpers that start with your Mac."
        }
    }
}

public enum SmartCareCardState: Equatable, Sendable {
    case scanning
    case ready
    case needsAccess(String)
    case blocked(String)
    case empty
    case failed(String)
}

/// One thing a card can free: a path, its bytes and how safe removing it is.
/// `protected` and `unclassified` entries are shown but never counted.
public struct SmartCareEntry: Equatable, Sendable {
    public let path: String
    public let bytes: Int64
    public let tier: StorageRecommendation

    public init(path: String, bytes: Int64, tier: StorageRecommendation) {
        self.path = path
        self.bytes = bytes
        self.tier = tier
    }
}

public struct SmartCareCard: Identifiable, Equatable, Sendable {
    public var id: SmartCareCardID { cardID }
    public let cardID: SmartCareCardID
    public let state: SmartCareCardState
    public let entries: [SmartCareEntry]
    /// Informational size for cards whose bytes are not made of entries
    /// (for example a snapshot estimate). Never added to a total.
    public let infoText: String?

    public init(
        cardID: SmartCareCardID,
        state: SmartCareCardState,
        entries: [SmartCareEntry] = [],
        infoText: String? = nil
    ) {
        self.cardID = cardID
        self.state = state
        self.entries = entries
        self.infoText = infoText
    }

    public var recommendedBytes: Int64 { bytes(for: .recommended) }
    public var reviewBytes: Int64 { bytes(for: .review) }
    public var protectedBytes: Int64 { bytes(for: .protected) }
    public var itemCount: Int { entries.count }

    public func bytes(for tier: StorageRecommendation) -> Int64 {
        entries.filter { $0.tier == tier }.reduce(0) { $0 + $1.bytes }
    }

    /// Clean acts on recommended entries only, and only on a ready card.
    public var canClean: Bool {
        state == .ready && recommendedBytes > 0
    }

    public var isEmpty: Bool {
        if case .empty = state { return true }
        return false
    }
}

public struct SmartCareHeadline: Equatable, Sendable {
    /// Recommended bytes across all cards. Never includes review, protected
    /// or unclassified bytes.
    public let safeBytes: Int64
    public let reviewBytes: Int64

    public init(safeBytes: Int64, reviewBytes: Int64) {
        self.safeBytes = safeBytes
        self.reviewBytes = reviewBytes
    }
}
