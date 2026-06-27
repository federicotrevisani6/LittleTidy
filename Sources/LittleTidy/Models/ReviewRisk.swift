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
            return "Safe"
        case .review:
            return "Review"
        case .careful:
            return "Caution"
        }
    }

    /// Short explanation shown alongside the chip so the single signal is self-describing.
    var explanation: String {
        switch self {
        case .low:
            return "High confidence this is safe to remove."
        case .review:
            return "Worth a quick look before removing."
        case .careful:
            return "Low confidence — inspect carefully first."
        }
    }

    var systemImage: String {
        switch self {
        case .low:
            return "checkmark.shield"
        case .review:
            return "exclamationmark.triangle"
        case .careful:
            return "questionmark.diamond"
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

