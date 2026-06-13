import Foundation
import MacCleanerCore

struct ReviewItem: Identifiable, Hashable {
    let id = UUID()
    let category: CleanupCategory
    let title: String
    let detail: String
    let location: String
    let bytes: Int64
    let confidence: Confidence
    let reason: String
    let plannedURLs: [URL]
    var duplicateCopies: [DuplicateCopyReview]
    var relatedData: [RelatedAppData] = []
    var isSelected: Bool
}

struct DuplicateCopyReview: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let bytes: Int64
    let isRecommendedKeep: Bool
    var isSelected: Bool
}
