import AppKit
import LittleTidyCore
import SwiftUI

struct DeveloperStorageView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingCleanupConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeveloperStorageHeader(
                isScanning: store.isScanningDeveloperStorage,
                totalBytes: store.totalDeveloperBytes,
                refresh: store.refreshDeveloperStorage
            )

            if let error = store.developerStorageErrorMessage {
                DeveloperStorageErrorBanner(message: error, retry: store.refreshDeveloperStorage)
            }

            DeveloperStorageSummary(
                recommendedBytes: store.recommendedDeveloperBytes,
                reviewBytes: store.reviewDeveloperBytes,
                protectedBytes: store.protectedDeveloperBytes,
                unclassifiedBytes: store.unclassifiedDeveloperBytes
            )

            if !store.selectedDeveloperStorageItems.isEmpty {
                DeveloperStorageCleanupBar(
                    selectedCount: store.selectedDeveloperStorageItems.count,
                    selectedBytes: store.selectedDeveloperStorageBytes,
                    hasIrreversibleOperations: store.selectedDeveloperStorageHasIrreversibleOperations,
                    isCleaning: store.isCleaningDeveloperStorage
                ) {
                    showingCleanupConfirmation = true
                }
            }

            if let result = store.developerCleanupResult {
                DeveloperStorageCleanupResultBanner(result: result)
            }

            if store.developerStorageInventory.items.isEmpty, !store.isScanningDeveloperStorage {
                DeveloperStorageEmptyState()
            } else {
                ForEach(DeveloperStorageCategory.allCases, id: \.self) { category in
                    let items = store.developerItems(for: category)
                    if !items.isEmpty {
                        DeveloperStorageCategorySection(
                            category: category,
                            items: items,
                            selectedIDs: store.selectedDeveloperStorageItemIDs,
                            canSelect: store.canSelectDeveloperStorageItem,
                            toggle: store.toggleDeveloperStorageItem
                        )
                    }
                }
            }

            if !store.developerStorageInventory.accessIssues.isEmpty {
                DeveloperStorageAccessIssues(issues: store.developerStorageInventory.accessIssues)
            }
        }
        .confirmationDialog(
            store.selectedDeveloperStorageHasIrreversibleOperations
                ? "Clean selected developer storage? Some Simulator operations cannot be undone."
                : "Move selected developer storage to the Trash?",
            isPresented: $showingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                store.selectedDeveloperStorageHasIrreversibleOperations ? "Clean Selected" : "Move to Trash",
                role: .destructive,
                action: store.executeDeveloperStorageCleanup
            )
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(store.selectedDeveloperStorageItems.count) items · \(ByteCountFormatter.cleanerString(from: store.selectedDeveloperStorageBytes)). Rebuildable data may slow the next build; unavailable Simulator devices are removed with simctl.")
        }
    }
}

private struct DeveloperStorageHeader: View {
    let isScanning: Bool
    let totalBytes: Int64
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Developer Storage")
                    .font(.largeTitle.weight(.bold))
                Text("Find the Xcode, Simulator, and test data hidden inside System Data. LittleTidy separates safe cleanup from items that need review.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 680, alignment: .leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCountFormatter.cleanerString(from: totalBytes))
                    .font(.title2.weight(.bold))
                Text("identified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: refresh) {
                    Label(isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }
        }
        .padding(22)
        .cleanerSurface()
    }
}

private struct DeveloperStorageSummary: View {
    let recommendedBytes: Int64
    let reviewBytes: Int64
    let protectedBytes: Int64
    let unclassifiedBytes: Int64

    var body: some View {
        HStack(spacing: 12) {
            DeveloperStorageMetric(
                title: "Recommended",
                bytes: recommendedBytes,
                detail: "Rebuildable or unavailable",
                color: .cleanerSuccess,
                systemImage: "checkmark.seal"
            )
            DeveloperStorageMetric(
                title: "Review",
                bytes: reviewBytes,
                detail: "Check impact before removal",
                color: .cleanerWarning,
                systemImage: "eye"
            )
            DeveloperStorageMetric(
                title: "Protected",
                bytes: protectedBytes,
                detail: "Active or valuable history",
                color: .cleanerInfo,
                systemImage: "lock.shield"
            )
            DeveloperStorageMetric(
                title: "Unclassified",
                bytes: unclassifiedBytes,
                detail: "Diagnosis only",
                color: .secondary,
                systemImage: "questionmark.folder"
            )
        }
    }
}

private struct DeveloperStorageMetric: View {
    let title: String
    let bytes: Int64
    let detail: String
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(ByteCountFormatter.cleanerString(from: bytes))
                .font(.title2.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(14)
        .cleanerSubtleSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct DeveloperStorageCategorySection: View {
    let category: DeveloperStorageCategory
    let items: [DeveloperStorageItem]
    let selectedIDs: Set<String>
    let canSelect: (DeveloperStorageItem) -> Bool
    let toggle: (DeveloperStorageItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(category.displayName)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(ByteCountFormatter.cleanerString(from: items.reduce(0) { $0 + $1.bytes }))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(items) { item in
                    DeveloperStorageItemRow(
                        item: item,
                        isSelected: selectedIDs.contains(item.id),
                        isSelectable: canSelect(item),
                        toggle: { toggle(item) }
                    )
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .cleanerSubtleSurface()
        }
    }
}

private struct DeveloperStorageItemRow: View {
    let item: DeveloperStorageItem
    let isSelected: Bool
    let isSelectable: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!isSelectable)
            .opacity(isSelectable ? 1 : 0.35)
            .accessibilityLabel(isSelected ? "Deselect \(item.name)" : "Select \(item.name)")

            Image(systemName: recommendationIcon)
                .foregroundStyle(recommendationColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(recommendationTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(recommendationColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(recommendationColor.opacity(0.12), in: Capsule())
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.recommendationReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(ByteCountFormatter.cleanerString(from: item.bytes))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)

            if let url = item.url, FileManager.default.fileExists(atPath: url.path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(item.name) in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var recommendationTitle: String {
        switch item.recommendation {
        case .recommended: "Recommended"
        case .review: "Review"
        case .protected: "Protected"
        case .unclassified: "Unclassified"
        }
    }

    private var recommendationIcon: String {
        switch item.recommendation {
        case .recommended: "checkmark.seal.fill"
        case .review: "eye.fill"
        case .protected: "lock.shield.fill"
        case .unclassified: "questionmark.folder.fill"
        }
    }

    private var recommendationColor: Color {
        switch item.recommendation {
        case .recommended: .cleanerSuccess
        case .review: .cleanerWarning
        case .protected: .cleanerInfo
        case .unclassified: .secondary
        }
    }
}

private struct DeveloperStorageCleanupBar: View {
    let selectedCount: Int
    let selectedBytes: Int64
    let hasIrreversibleOperations: Bool
    let isCleaning: Bool
    let clean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasIrreversibleOperations ? "exclamationmark.shield" : "trash")
                .foregroundStyle(hasIrreversibleOperations ? Color.cleanerWarning : Color.cleanerSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) selected · \(ByteCountFormatter.cleanerString(from: selectedBytes))")
                    .font(.subheadline.weight(.semibold))
                Text(hasIrreversibleOperations ? "Includes Simulator operations that cannot be undone." : "Selected items will move to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: clean) {
                Label(isCleaning ? "Cleaning…" : "Review & Clean", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.glassProminent)
            .disabled(isCleaning)
        }
        .padding(14)
        .cleanerSubtleSurface()
    }
}

private struct DeveloperStorageCleanupResultBanner: View {
    let result: DeveloperStorageCleanupResult

    var body: some View {
        let removed = result.items.filter { $0.status == .removed }.count
        let failed = result.items.filter { $0.status == .failed }.count
        HStack(spacing: 10) {
            Label(
                "Cleanup complete: \(removed) removed · \(ByteCountFormatter.cleanerString(from: result.removedBytes))",
                systemImage: failed == 0 ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .foregroundStyle(failed == 0 ? Color.cleanerSuccess : Color.cleanerWarning)
            Spacer()
            if failed > 0 {
                Text("\(failed) failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cleanerDanger)
            }
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}

private struct DeveloperStorageErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.cleanerDanger)
            Spacer()
            Button("Try Again", action: retry)
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}

private struct DeveloperStorageEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No Developer Storage Found",
            systemImage: "externaldrive.badge.checkmark",
            description: Text("LittleTidy did not find Xcode, Simulator, or XCTest data in the standard locations.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct DeveloperStorageAccessIssues: View {
    let issues: [DeveloperStorageAccessIssue]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.path)
                            .font(.caption.monospaced())
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("\(issues.count) access or tool issues", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.cleanerWarning)
        }
        .padding(14)
        .cleanerSubtleSurface()
    }
}
