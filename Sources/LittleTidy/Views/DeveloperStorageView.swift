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

            if store.isXcodeRunning {
                DeveloperStorageXcodeRunningBanner()
            }

            if !store.selectedDeveloperStorageItems.isEmpty {
                DeveloperStorageCleanupBar(
                    selectedCount: store.selectedDeveloperStorageItems.count,
                    selectedBytes: store.selectedDeveloperStorageBytes,
                    hasIrreversibleOperations: store.selectedDeveloperStorageHasIrreversibleOperations,
                    isCleaning: store.isCleaningDeveloperStorage,
                    isXcodeRunning: store.isXcodeRunning
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
                            setSelection: store.setDeveloperStorageItemSelection
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
        .onAppear(perform: store.refreshXcodeRunningState)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            store.refreshXcodeRunningState()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            store.refreshXcodeRunningState()
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
    let setSelection: (DeveloperStorageItem, Bool) -> Void

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
                        setSelection: { setSelection(item, $0) }
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
    let setSelection: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelectable {
                Toggle("Select \(item.name)", isOn: Binding(
                    get: { isSelected },
                    set: { newValue in setSelection(newValue) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.regular)
                .accessibilityLabel(isSelected ? "Deselect \(item.name)" : "Select \(item.name)")
                .accessibilityHint("Adds or removes this item from developer storage cleanup.")
                .help(isSelected ? "Remove from cleanup selection" : "Add to cleanup selection")
            } else {
                Image(systemName: item.activity == .active ? "lock.fill" : "nosign")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityLabel(item.activity == .active ? "Protected while active" : "No supported cleanup action")
                    .help(item.activity == .active ? "Quit or shut down this item before selecting it." : "LittleTidy has no verified cleanup action for this item.")
            }

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
    let isXcodeRunning: Bool
    let clean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasIrreversibleOperations ? "exclamationmark.shield" : "trash")
                .foregroundStyle(hasIrreversibleOperations ? Color.cleanerWarning : Color.cleanerSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) selected · \(ByteCountFormatter.cleanerString(from: selectedBytes))")
                    .font(.subheadline.weight(.semibold))
                Text(cleanupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: clean) {
                Label(isCleaning ? "Cleaning…" : "Review & Clean", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.glassProminent)
            .disabled(isCleaning || isXcodeRunning)
            .help(isXcodeRunning ? "Quit Xcode before cleaning developer storage." : "Review the selected cleanup actions.")
        }
        .padding(14)
        .cleanerSubtleSurface()
    }

    private var cleanupDescription: String {
        if isXcodeRunning {
            return "Quit Xcode to enable cleanup. No developer data can be removed while it is open."
        }
        return hasIrreversibleOperations
            ? "Includes Simulator operations that cannot be undone."
            : "Selected items will move to the Trash."
    }
}

private struct DeveloperStorageXcodeRunningBanner: View {
    var body: some View {
        Label(
            "Xcode is open. Quit Xcode before cleaning developer storage; selection remains available for review.",
            systemImage: "lock.shield.fill"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.cleanerWarning)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerSubtleSurface()
        .accessibilityLabel("Developer storage cleanup locked because Xcode is open")
    }
}

private struct DeveloperStorageCleanupResultBanner: View {
    let result: DeveloperStorageCleanupResult

    var body: some View {
        let removed = result.items.filter { $0.status == .removed }.count
        let skipped = result.items.filter { $0.status == .skipped }.count
        let failed = result.items.filter { $0.status == .failed }.count
        let hasWarnings = skipped > 0 || failed > 0
        HStack(spacing: 10) {
            Label(
                "Cleanup complete: \(removed) removed · \(ByteCountFormatter.cleanerString(from: result.removedBytes))",
                systemImage: hasWarnings ? "exclamationmark.triangle" : "checkmark.circle"
            )
            .foregroundStyle(hasWarnings ? Color.cleanerWarning : Color.cleanerSuccess)
            Spacer()
            if skipped > 0 {
                Text("\(skipped) skipped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cleanerWarning)
            }
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
