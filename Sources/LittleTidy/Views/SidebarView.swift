import LittleTidyCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        List(selection: $store.selectedSection) {
            ForEach(SidebarSection.allCases) { section in
                HStack(spacing: 10) {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .lineLimit(1)
                        Text(detail(for: section))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LittleTidy")
    }

    private func detail(for section: SidebarSection) -> String {
        switch section {
        case .overview:
            store.isScanning ? "Scanning" : "Ready"
        case .duplicates:
            ByteCountFormatter.cleanerString(from: store.reclaimableBytes(for: .duplicate))
        case .largeFiles:
            ByteCountFormatter.cleanerString(from: store.reclaimableBytes(for: .largeFile))
        case .unusedApps:
            ByteCountFormatter.cleanerString(from: store.reclaimableBytes(for: .unusedApp))
        case .caches:
            ByteCountFormatter.cleanerString(from: store.reclaimableBytes(for: .cache))
        case .storage:
            store.folderUsage.isEmpty ? "—" : "\(store.folderUsage.count) folders"
        case .cleanupPlan:
            "\(store.selectedItems.count) selected"
        }
    }
}
