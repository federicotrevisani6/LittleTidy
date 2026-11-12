import Foundation

extension DeveloperStorageItem {
    /// Whether a person may pick this item for cleanup at all. One rule shared
    /// by the Developer Storage list and Smart Care's "Clean all safe".
    public var isUserSelectable: Bool {
        guard activity != .active, recommendation != .unclassified else { return false }
        switch cleanupMechanism {
        case .trash:
            return true
        case .simctl:
            return category == .simulatorDevices || category == .xctestDevices
        case .xcodeManaged:
            return category == .simulatorRuntimes && recommendation == .review
        case .homebrewCleanup:
            return true
        case .manual, .unsupported:
            return false
        }
    }

    /// Removal that cannot be undone from the Trash: anything not simply moved there,
    /// or data the user would have to download or install again.
    public var isIrreversibleCleanup: Bool {
        cleanupMechanism == .simctl
            || cleanupMechanism == .xcodeManaged
            || cleanupMechanism == .homebrewCleanup
            || recoverability == .irreversible
            || recoverability == .reinstallable
    }
}

/// What "Clean all safe" would do right now. It is a preview: the executor
/// rechecks every safety rule for each item when it runs, and may still skip
/// items that became unsafe since this plan was built.
public struct SmartCareCleanPlan: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: SmartCareCardID { cardID }
        public let cardID: SmartCareCardID
        public let itemCount: Int
        public let bytes: Int64
        public let irreversibleCount: Int
    }

    public struct Skipped: Equatable, Sendable, Identifiable {
        public var id: String { itemID }
        public let itemID: String
        public let name: String
        public let reason: String
        public let bytes: Int64
    }

    /// Items to hand to the cleanup executor, in display order.
    public let items: [DeveloperStorageItem]
    public let groups: [Group]
    public let skipped: [Skipped]

    public var itemCount: Int { items.count }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var irreversibleItems: [DeveloperStorageItem] { items.filter(\.isIrreversibleCleanup) }
    public var hasIrreversibleItems: Bool { items.contains { $0.isIrreversibleCleanup } }
    public var isEmpty: Bool { items.isEmpty }
}

public enum SmartCareCleanPlanner {
    private static let aiCategories: Set<DeveloperStorageCategory> = [.aiModelsAndAgents, .aiCaches, .aiGeneratedArtifacts]
    /// The mechanisms the app already preselects for recommended developer
    /// items. Runtime deletion stays a deliberate, reviewed choice.
    private static let allowedMechanisms: Set<DeveloperCleanupMechanism> = [.trash, .simctl, .homebrewCleanup]

    public static func cardID(for item: DeveloperStorageItem) -> SmartCareCardID {
        aiCategories.contains(item.category) ? .aiTools : .developer
    }

    public static func cardID(forItemID id: String, in items: [DeveloperStorageItem]) -> SmartCareCardID? {
        items.first { $0.id == id }.map(cardID(for:))
    }

    /// Only `recommended` items qualify: never review, protected or
    /// unclassified ones, and never the Trash.
    public static func plan(from inventory: [DeveloperStorageItem], xcodeIsRunning: Bool) -> SmartCareCleanPlan {
        var included: [DeveloperStorageItem] = []
        var skipped: [SmartCareCleanPlan.Skipped] = []

        for item in inventory {
            guard item.recommendation == .recommended,
                  item.isUserSelectable,
                  allowedMechanisms.contains(item.cleanupMechanism),
                  item.bytes > 0 else { continue }

            if xcodeIsRunning, item.xcodeActivityRule == .requiresXcodeQuit {
                skipped.append(.init(itemID: item.id, name: item.name, reason: "Quit Xcode to clean this item.", bytes: item.bytes))
                continue
            }
            included.append(item)
        }

        let groups = SmartCareCardID.allCases.compactMap { card -> SmartCareCleanPlan.Group? in
            let members = included.filter { cardID(for: $0) == card }
            guard !members.isEmpty else { return nil }
            return .init(
                cardID: card,
                itemCount: members.count,
                bytes: members.reduce(0) { $0 + $1.bytes },
                irreversibleCount: members.filter(\.isIrreversibleCleanup).count
            )
        }

        // Largest first, so the sheet leads with what matters most.
        let ordered = included.sorted { $0.bytes > $1.bytes }
        return SmartCareCleanPlan(items: ordered, groups: groups, skipped: skipped)
    }
}
