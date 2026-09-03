import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case storage
    case developerStorage
    case unusedApps
    case duplicates
    case largeFiles
    case caches
    case cleanupPlan

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case system
        case cleanup
        case review

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .cleanup: "Cleanup"
            case .review: "Review"
            }
        }

        var sections: [SidebarSection] {
            switch self {
            case .system: [.overview, .storage]
            case .cleanup: [.developerStorage, .caches, .duplicates, .largeFiles, .unusedApps]
            case .review: [.cleanupPlan]
            }
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .developerStorage: "Developer Storage"
        case .duplicates: "Duplicate Files"
        case .largeFiles: "Large Files"
        case .unusedApps: "Applications"
        case .caches: "Application Caches"
        case .storage: "Storage Map"
        case .cleanupPlan: "Cleanup Plan"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.needle"
        case .developerStorage: "hammer"
        case .duplicates: "doc.on.doc"
        case .largeFiles: "internaldrive"
        case .unusedApps: "app.badge"
        case .caches: "shippingbox"
        case .storage: "chart.pie"
        case .cleanupPlan: "trash"
        }
    }
}
