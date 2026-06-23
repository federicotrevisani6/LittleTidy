import Foundation
import LittleTidyCore

enum ReviewRisk: String, CaseIterable, Identifiable {
    case low
    case review
    case careful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low risk"
        case .review:
            return "Review"
        case .careful:
            return "Careful"
        }
    }

    static func risk(for confidence: Confidence) -> ReviewRisk {
        switch confidence {
        case .high:
            return .low
        case .medium:
            return .review
        case .low:
            return .careful
        }
    }
}

