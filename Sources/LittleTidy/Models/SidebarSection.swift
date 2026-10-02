import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case systemDiagnosis
    case maintenance
    case protection
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
            case .system: [.overview, .systemDiagnosis, .storage, .maintenance, .protection]
            case .cleanup: [.developerStorage, .caches, .duplicates, .largeFiles, .unusedApps]
            case .review: [.cleanupPlan]
            }
        }
    }

    var title: String {
        switch self {
        case .systemDiagnosis: "System Diagnosis"
        case .maintenance: "Maintenance"
        case .protection: "Protection"
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
        case .systemDiagnosis: "internaldrive.fill"
        case .maintenance: "wrench.and.screwdriver"
        case .protection: "shield.lefthalf.filled"
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

    var isSystemCare: Bool { self == .systemDiagnosis || self == .maintenance || self == .protection }

    var supportsItemSearch: Bool {
        switch self {
        case .duplicates, .largeFiles, .unusedApps, .caches:
            true
        case .overview, .storage, .developerStorage, .cleanupPlan, .systemDiagnosis, .maintenance, .protection:
            false
        }
    }
}
