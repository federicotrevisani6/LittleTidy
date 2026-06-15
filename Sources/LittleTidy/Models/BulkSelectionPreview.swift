import Foundation
import LittleTidyCore

enum BulkSelectionMode {
    case suggestedWithoutCaches
    case reviewedCaches
}

struct BulkSelectionPreview {
    struct CategoryBreakdown: Identifiable {
        let category: CleanupCategory
        let itemCount: Int
        let filesystemEntryCount: Int
        let bytes: Int64

        var id: CleanupCategory { category }
    }

    let mode: BulkSelectionMode
    let itemCount: Int
    let filesystemEntryCount: Int
    let bytes: Int64
    let categoryBreakdown: [CategoryBreakdown]
    let excludedCacheItemCount: Int
    let excludedCacheBytes: Int64

    var hasItems: Bool {
        itemCount > 0
    }

    var excludesCaches: Bool {
        excludedCacheItemCount > 0 || excludedCacheBytes > 0
    }
}

extension CleanupCategory {
    var displayTitle: String {
        switch self {
        case .duplicate:
            return "Duplicates"
        case .largeFile:
            return "Large Files"
        case .unusedApp:
            return "Unused Apps"
        case .cache:
            return "Caches"
        }
    }
}
