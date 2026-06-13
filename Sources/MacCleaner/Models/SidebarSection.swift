import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case duplicates
    case largeFiles
    case unusedApps
    case caches
    case cleanupPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .duplicates: "Duplicates"
        case .largeFiles: "Large Files"
        case .unusedApps: "Unused Apps"
        case .caches: "Caches"
        case .cleanupPlan: "Cleanup Plan"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.bottom.50percent"
        case .duplicates: "doc.on.doc"
        case .largeFiles: "internaldrive"
        case .unusedApps: "app.dashed"
        case .caches: "shippingbox"
        case .cleanupPlan: "trash"
        }
    }
}
