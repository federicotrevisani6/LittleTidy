import Foundation

enum ReviewFilterScope: String, CaseIterable, Identifiable {
    case all
    case selected
    case unselected
    case highConfidence
    case needsReview
    case includesRelatedData
    case failedLastCleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .selected:
            return "Selected"
        case .unselected:
            return "Unselected"
        case .highConfidence:
            return "High Confidence"
        case .needsReview:
            return "Needs Review"
        case .includesRelatedData:
            return "Related Data"
        case .failedLastCleanup:
            return "Failed Last Cleanup"
        }
    }
}
