import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case duplicates
    case largeFiles
    case unusedApps
    case caches
    case storage
    case cleanupPlan

    var id: String { rawValue }

    /// Sections shown in the sidebar, grouped. The cleanup plan is reached via
    /// the cleanup cart bar rather than as a top-level sidebar peer.
    enum Group: String, CaseIterable, Identifiable {
        case clean
        case review
        case explore

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clean: "Clean"
            case .review: "Review"
            case .explore: "Explore"
            }
        }

        var sections: [SidebarSection] {
            switch self {
            case .clean: [.overview]
            case .review: [.duplicates, .largeFiles, .unusedApps, .caches]
            case .explore: [.storage]
            }
        }
    }

    var title: String {
        switch self {
        case .overview: "Home"
        case .duplicates: "Duplicates"
        case .largeFiles: "Large Files"
        case .unusedApps: "Unused Apps"
        case .caches: "Caches"
        case .storage: "Storage Map"
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
        case .storage: "square.grid.2x2"
        case .cleanupPlan: "trash"
        }
    }
}
