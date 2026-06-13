import Foundation

struct PermissionReadinessItem: Identifiable {
    enum Severity {
        case ready
        case advisory
        case warning
    }

    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity
    let url: URL?
}
