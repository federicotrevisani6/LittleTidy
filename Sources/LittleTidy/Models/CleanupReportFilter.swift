import Foundation

enum CleanupReportFilter: String, CaseIterable, Identifiable {
    case all
    case moved
    case skipped
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .moved:
            return "Moved"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Failed"
        }
    }
}

