import Foundation
import LittleTidyCore

/// A persisted record of one completed cleanup run.
struct CleanupHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let bytesFreed: Int64
    let movedCount: Int
    let skippedCount: Int
    let failedCount: Int
    /// Bytes moved to Trash per category, keyed by `CleanupCategory.rawValue`.
    let bytesByCategory: [String: Int64]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        bytesFreed: Int64,
        movedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        bytesByCategory: [String: Int64]
    ) {
        self.id = id
        self.date = date
        self.bytesFreed = bytesFreed
        self.movedCount = movedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.bytesByCategory = bytesByCategory
    }
}
