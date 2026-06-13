import Foundation

struct ScanIssue: Identifiable, Hashable {
    enum Kind: String {
        case skipped = "Skipped"
        case permissionDenied = "Permission"
    }

    let id = UUID()
    let kind: Kind
    let url: URL
    let message: String
}
