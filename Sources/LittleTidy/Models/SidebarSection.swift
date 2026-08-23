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
        case clean
        case tools
        case explore

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clean: "Pulizia Rapida"
            case .tools: "Strumenti"
            case .explore: "Analisi Disco"
            }
        }

        var sections: [SidebarSection] {
            switch self {
            case .clean: [.overview]
            case .tools: [.developerStorage, .unusedApps, .duplicates, .largeFiles, .caches]
            case .explore: [.storage]
            }
        }
    }

    var title: String {
        switch self {
        case .overview: "Smart Clean"
        case .developerStorage: "Xcode & Developer"
        case .duplicates: "File Duplicati"
        case .largeFiles: "Grandi File"
        case .unusedApps: "App & Residui"
        case .caches: "Cache di Sistema"
        case .storage: "Mappa Spazio"
        case .cleanupPlan: "Piano di Pulizia"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "sparkles"
        case .developerStorage: "hammer.fill"
        case .duplicates: "doc.on.doc.fill"
        case .largeFiles: "internaldrive.fill"
        case .unusedApps: "app.badge.checkmark"
        case .caches: "shippingbox.fill"
        case .storage: "chart.pie.fill"
        case .cleanupPlan: "trash.fill"
        }
    }
}
