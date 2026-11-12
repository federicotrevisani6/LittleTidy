import Foundation

/// An honest account of one cleanup run. Moving to the Trash frees no space
/// until the Trash is emptied, so the numbers are kept apart and the screen
/// never calls Trash-held bytes "freed".
public struct CleanupSummary: Equatable, Sendable {
    public struct CardLine: Equatable, Sendable, Identifiable {
        public var id: SmartCareCardID { cardID }
        public let cardID: SmartCareCardID
        public let removedCount: Int
        public let bytes: Int64
    }

    public struct Problem: Equatable, Sendable, Identifiable {
        public var id: String { itemID }
        public let itemID: String
        public let name: String
        public let reason: String
    }

    /// Removed for good (simctl, brew, and so on) and not held by a snapshot.
    public let freedNowBytes: Int64
    /// Moved to the Trash: freed when the Trash is emptied.
    public let inTrashBytes: Int64
    /// Removed for good, but a Time Machine local snapshot still holds the
    /// space. Nil unless the gap is meaningful.
    public let heldBySnapshotBytes: Int64?
    public let removedCount: Int
    public let lines: [CardLine]
    public let skipped: [Problem]
    public let failed: [Problem]
    /// Items that went to the Trash and can be put back.
    public let restorable: [RestorableItem]
    /// Removed items that cannot be restored (not moved to the Trash).
    public let irreversibleCount: Int

    public var hasProblems: Bool { !skipped.isEmpty || !failed.isEmpty }

    public static func make(
        from result: DeveloperStorageCleanupResult,
        items: [DeveloperStorageItem]
    ) -> CleanupSummary {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = result.items.filter { $0.status == .removed }

        let removedForGood = removed.filter { !$0.movedToTrash }.reduce(Int64(0)) { $0 + $1.bytes }
        let held = result.bytesNotYetFreed.flatMap { value -> Int64? in
            value >= max(100_000_000, removedForGood / 10) ? min(value, removedForGood) : nil
        }
        let freedNow = max(0, removedForGood - (held ?? 0))

        let cards = SmartCareCardID.allCases.compactMap { card -> CardLine? in
            let members = removed.filter { entry in
                byID[entry.itemID].map(SmartCareCleanPlanner.cardID(for:)).map { $0 == card } ?? (card == .developer)
            }
            guard !members.isEmpty else { return nil }
            return CardLine(cardID: card, removedCount: members.count, bytes: members.reduce(0) { $0 + $1.bytes })
        }

        func problems(_ status: DeveloperStorageCleanupStatus) -> [Problem] {
            result.items.filter { $0.status == status }.map {
                Problem(itemID: $0.itemID, name: $0.name, reason: $0.message)
            }
        }

        let restorable = removed.compactMap { entry -> RestorableItem? in
            guard entry.movedToTrash, let original = entry.originalPath, let trash = entry.trashPath else { return nil }
            return RestorableItem(name: entry.name, originalURL: URL(fileURLWithPath: original), trashURL: URL(fileURLWithPath: trash))
        }

        return CleanupSummary(
            freedNowBytes: freedNow,
            inTrashBytes: result.bytesInTrash,
            heldBySnapshotBytes: held,
            removedCount: removed.count,
            lines: cards,
            skipped: problems(.skipped),
            failed: problems(.failed),
            restorable: restorable,
            irreversibleCount: removed.filter { !$0.movedToTrash }.count
        )
    }
}
