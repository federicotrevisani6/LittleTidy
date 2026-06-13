import Foundation

enum ReviewFilterScope: String, CaseIterable, Identifiable {
    case all
    case selected
    case highConfidence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .selected:
            return "Selected"
        case .highConfidence:
            return "High"
        }
    }
}
