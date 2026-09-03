import LittleTidyCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        List(selection: $store.selectedSection) {
            ForEach(SidebarSection.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        SidebarRow(section: section, store: store)
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LittleTidy")
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(badgeText(for: section))
    }

    private func badgeText(for section: SidebarSection) -> String {
        switch section {
        case .overview:
            if store.isScanning { return "…" }
            let total = store.reclaimableBytes(for: .cache) + store.reclaimableBytes(for: .duplicate) + store.recommendedDeveloperBytes
            return total > 0 ? ByteCountFormatter.cleanerString(from: total) : ""
        case .developerStorage:
            if store.isScanningDeveloperStorage { return "…" }
            return store.totalDeveloperBytes > 0 ? ByteCountFormatter.cleanerString(from: store.totalDeveloperBytes) : ""
        case .duplicates:
            let bytes = store.reclaimableBytes(for: .duplicate)
            return bytes > 0 ? ByteCountFormatter.cleanerString(from: bytes) : ""
        case .largeFiles:
            let bytes = store.reclaimableBytes(for: .largeFile)
            return bytes > 0 ? ByteCountFormatter.cleanerString(from: bytes) : ""
        case .unusedApps:
            let bytes = store.reclaimableBytes(for: .unusedApp)
            return bytes > 0 ? ByteCountFormatter.cleanerString(from: bytes) : ""
        case .caches:
            let bytes = store.reclaimableBytes(for: .cache)
            return bytes > 0 ? ByteCountFormatter.cleanerString(from: bytes) : ""
        case .storage:
            return store.folderUsage.isEmpty ? "" : "\(store.folderUsage.count)"
        case .cleanupPlan:
            return store.selectedItems.isEmpty ? "" : "\(store.selectedItems.count)"
        }
    }
}
