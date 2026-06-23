import LittleTidyCore
import SwiftUI

struct DetailView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = store.bulkSelectionUndoMessage {
                    BulkSelectionUndoBanner(message: message) {
                        store.undoBulkSelection()
                    } viewPlan: {
                        store.selectedSection = .cleanupPlan
                    }
                }

                switch store.selectedSection {
                case .overview:
                    OverviewView(store: store)
                case .duplicates:
                    ReviewListView(
                        title: "Duplicate Files",
                        subtitle: "Byte-identical copies confirmed by hash.",
                        items: store.items(for: .duplicate),
                        category: .duplicate,
                        store: store
                    )
                case .largeFiles:
                    ReviewListView(
                        title: "Large Files",
                        subtitle: "Ranked by size, age, location, and file type.",
                        items: store.items(for: .largeFile),
                        category: .largeFile,
                        store: store
                    )
                case .unusedApps:
                    ReviewListView(
                        title: "Unused Apps",
                        subtitle: store.includeRelatedAppData ? "App bundles and matched related app data are included when selected." : "App bundles only. Related app data stays excluded unless you enable deep uninstall.",
                        items: store.items(for: .unusedApp),
                        category: .unusedApp,
                        store: store
                    )
                case .caches:
                    ReviewListView(
                        title: "Caches",
                        subtitle: "Regenerable app and developer caches. Cleared safely to the Trash.",
                        items: store.items(for: .cache),
                        category: .cache,
                        store: store
                    )
                case .storage:
                    StorageMapView(store: store)
                case .cleanupPlan:
                    CleanupPlanView(store: store)
                }
            }
            .padding(24)
        }
    }
}

private struct BulkSelectionUndoBanner: View {
    let message: String
    let undo: () -> Void
    let viewPlan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.cleanerSuccess)
            Spacer()
            Button("Undo", action: undo)
            Button("View Cleanup Plan", action: viewPlan)
                .buttonStyle(.glass)
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}
