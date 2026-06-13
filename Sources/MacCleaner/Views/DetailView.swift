import MacCleanerCore
import SwiftUI

struct DetailView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch store.selectedSection {
                case .overview:
                    OverviewView(store: store)
                case .duplicates:
                    ReviewListView(
                        title: "Duplicate Files",
                        subtitle: "Byte-identical copies confirmed by hash.",
                        items: store.items(for: .duplicate),
                        store: store
                    )
                case .largeFiles:
                    ReviewListView(
                        title: "Large Files",
                        subtitle: "Ranked by size, age, location, and file type.",
                        items: store.items(for: .largeFile),
                        store: store
                    )
                case .unusedApps:
                    ReviewListView(
                        title: "Unused Apps",
                        subtitle: "App bundles only. Related app data is not selected in v1.",
                        items: store.items(for: .unusedApp),
                        store: store
                    )
                case .cleanupPlan:
                    CleanupPlanView(store: store)
                }
            }
            .padding(24)
        }
    }
}
