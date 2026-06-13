import Foundation
import MacCleanerCore

struct CleanupReportItem: Identifiable, Hashable {
    enum Status: String {
        case moved = "Moved"
        case skipped = "Skipped"
        case failed = "Failed"
    }

    let id = UUID()
    let sourceURL: URL
    let destinationURL: URL?
    let status: Status
    let message: String
    let category: CleanupCategory?
    let bytes: Int64
}
