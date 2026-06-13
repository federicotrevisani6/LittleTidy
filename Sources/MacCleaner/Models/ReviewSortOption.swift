import Foundation

enum ReviewSortOption: String, CaseIterable, Identifiable {
    case largestFirst
    case smallestFirst
    case name
    case confidence
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largestFirst:
            return "Largest"
        case .smallestFirst:
            return "Smallest"
        case .name:
            return "Name"
        case .confidence:
            return "Confidence"
        case .location:
            return "Location"
        }
    }
}
