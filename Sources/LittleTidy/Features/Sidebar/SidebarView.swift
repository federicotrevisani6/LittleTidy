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
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(iconColor(for: section))
                .frame(width: 18)

            Text(section.title)
                .lineLimit(1)

            Spacer()

            badgeView(for: section)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func badgeView(for section: SidebarSection) -> some View {
        let text = badgeText(for: section)
        if !text.isEmpty {
            Text(text)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(badgeForeground(for: section))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeBackground(for: section))
                .clipShape(Capsule())
        }
    }

    private func badgeText(for section: SidebarSection) -> String {
        switch section {
        case .overview:
            if store.isScanning { return "Scansione..." }
            let total = store.reclaimableBytes(for: .cache) + store.reclaimableBytes(for: .duplicate) + store.recommendedDeveloperBytes
            return total > 0 ? ByteCountFormatter.cleanerString(from: total) : ""
        case .developerStorage:
            if store.isScanningDeveloperStorage { return "..." }
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
            return store.folderUsage.isEmpty ? "" : "\(store.folderUsage.count) cartelle"
        case .cleanupPlan:
            return store.selectedItems.isEmpty ? "" : "\(store.selectedItems.count)"
        }
    }

    private func iconColor(for section: SidebarSection) -> Color {
        switch section {
        case .overview: return .accentColor
        case .developerStorage: return .blue
        case .duplicates: return .orange
        case .largeFiles: return .purple
        case .unusedApps: return .pink
        case .caches: return .green
        case .storage: return .teal
        case .cleanupPlan: return .red
        }
    }

    private func badgeForeground(for section: SidebarSection) -> Color {
        switch section {
        case .overview: return .white
        case .cleanupPlan: return .white
        default: return .secondary
        }
    }

    private func badgeBackground(for section: SidebarSection) -> Color {
        switch section {
        case .overview: return .accentColor.opacity(0.85)
        case .cleanupPlan: return .red.opacity(0.85)
        default: return Color.primary.opacity(0.08)
        }
    }
}
