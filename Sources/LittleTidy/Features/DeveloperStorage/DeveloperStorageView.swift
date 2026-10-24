import AppKit
import LittleTidyCore
import SwiftUI

struct DeveloperStorageView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingCleanupConfirmation = false
    @State private var showingSnapshotReleaseConfirmation = false

    var body: some View {
        ScrollView {
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
                    recommendedGuaranteedBytes: store.recommendedDeveloperGuaranteedBytes,
                    reviewBytes: store.reviewDeveloperBytes,
                    protectedBytes: store.protectedDeveloperBytes,
                    unclassifiedBytes: store.unclassifiedDeveloperBytes
                )

                if let heldBytes = store.recommendedDeveloperBytesHeldBySnapshot,
                   let snapshotDate = store.developerStorageInventory.latestLocalSnapshotAt {
                    DeveloperStorageSnapshotBanner(heldBytes: heldBytes, snapshotDate: snapshotDate)
                }

                if store.isXcodeRunning {
                    DeveloperStorageXcodeRunningBanner()
                }

                if !store.selectedDeveloperStorageItems.isEmpty {
                    DeveloperStorageCleanupBar(
                        selectedCount: store.selectedDeveloperStorageItems.count,
                        selectedBytes: store.selectedDeveloperStorageBytes,
                        selectedGuaranteedBytes: store.selectedDeveloperStorageGuaranteedBytes,
                        hasIrreversibleOperations: store.selectedDeveloperStorageHasIrreversibleOperations,
                        isCleaning: store.isCleaningDeveloperStorage,
                        isXcodeRunning: store.isXcodeRunning,
                        itemsWaitingForXcode: store.selectedDeveloperStorageItemsWaitingForXcode
                    ) {
                        showingCleanupConfirmation = true
                    }
                }

                if let result = store.developerCleanupResult {
                    DeveloperStorageCleanupResultBanner(result: result)
                }

                if store.snapshotReleasableBytes != nil || store.isReleasingSnapshotSpace
                    || store.snapshotReleaseResult != nil || store.snapshotReleaseErrorMessage != nil {
                    DeveloperStorageSnapshotReleasePanel(
                        releasableBytes: store.snapshotReleasableBytes,
                        isReleasing: store.isReleasingSnapshotSpace,
                        result: store.snapshotReleaseResult,
                        errorMessage: store.snapshotReleaseErrorMessage
                    ) {
                        showingSnapshotReleaseConfirmation = true
                    }
                }

                if store.developerStorageInventory.items.isEmpty, !store.isScanningDeveloperStorage {
                    DeveloperStorageEmptyState()
                } else {
                    ForEach(orderedCategories, id: \.self) { category in
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
            .padding(24)
        }
        .confirmationDialog(
            store.selectedDeveloperStorageHasIrreversibleOperations
                ? "Clean selected developer storage? Some operations cannot be undone."
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
            Text("\(store.selectedDeveloperStorageItems.count) items · \(ByteCountFormatter.cleanerString(from: store.selectedDeveloperStorageBytes)). Rebuildable data may slow the next build. Simulator and XCTest devices are removed with simctl, and old Homebrew versions with brew cleanup.\(store.isXcodeRunning ? " Xcode is open, so anything it is using will be skipped." : "")")
        }
        .confirmationDialog(
            "Release space held by Time Machine local snapshots?",
            isPresented: $showingSnapshotReleaseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Release Space", role: .destructive, action: store.releaseSnapshotSpace)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(snapshotReleaseMessage)
        }
        .onAppear(perform: store.refreshXcodeRunningState)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            store.refreshXcodeRunningState()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            store.refreshXcodeRunningState()
        }
    }

    private var snapshotReleaseMessage: String {
        let bytes = ByteCountFormatter.cleanerString(from: store.snapshotReleasableBytes ?? 0)
        var message = "macOS removes local snapshots, oldest first, until about \(bytes) can be reclaimed. You lose the hourly restore points they contain; backups on a Time Machine disk are not affected. This cannot be undone."
        if let inTrash = store.developerCleanupResult?.bytesInTrash, inTrash > 0 {
            message += " Empty the Trash first: \(ByteCountFormatter.cleanerString(from: inTrash)) is still there, and macOS may remove every local snapshot trying to reclaim it."
        }
        return message
    }

    private var orderedCategories: [DeveloperStorageCategory] {
        DeveloperStorageCategory.allCases
            .filter { !store.developerItems(for: $0).isEmpty }
            .sorted { lhs, rhs in
                let lhsRank = categoryRank(lhs)
                let rhsRank = categoryRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return DeveloperStorageCategory.allCases.firstIndex(of: lhs) ?? 0
                    < DeveloperStorageCategory.allCases.firstIndex(of: rhs) ?? 0
            }
    }

    private func categoryRank(_ category: DeveloperStorageCategory) -> Int {
        let items = store.developerItems(for: category)
        if items.contains(where: { store.selectedDeveloperStorageItemIDs.contains($0.id) }) { return 0 }
        if items.contains(where: { $0.recommendation == .recommended }) { return 1 }
        if items.contains(where: { $0.recommendation == .review }) { return 2 }
        if items.contains(where: { $0.recommendation == .protected }) { return 3 }
        return 4
    }
}

private struct DeveloperStorageHeader: View {
    let isScanning: Bool
    let totalBytes: Int64
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer Storage")
                    .font(.title2.weight(.semibold))
                Text("Xcode data, simulators, package managers, and local AI models, caches, and sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 680, alignment: .leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(ByteCountFormatter.cleanerString(from: totalBytes))
                    .font(.title3.weight(.bold).monospacedDigit())
                Button(action: refresh) {
                    Label(isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
                .controlSize(.small)
            }
        }
        .padding(16)
        .cleanerSurface()
    }
}

private struct DeveloperStorageSummary: View {
    let recommendedBytes: Int64
    let recommendedGuaranteedBytes: Int64
    let reviewBytes: Int64
    let protectedBytes: Int64
    let unclassifiedBytes: Int64

    var body: some View {
        HStack(spacing: 12) {
            DeveloperStorageMetric(
                title: "Recommended",
                bytes: recommendedBytes,
                detail: recommendedGuaranteedBytes < recommendedBytes
                    ? "At least \(ByteCountFormatter.cleanerString(from: recommendedGuaranteedBytes)) freed right away"
                    : "Rebuildable or unavailable",
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.cleanerString(from: item.bytes))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if item.hasSharedStorage {
                    Text("≥ \(ByteCountFormatter.cleanerString(from: item.guaranteedReclaimableBytes)) now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Part of this item is shared with APFS clones or held by a Time Machine local snapshot. Removing it frees at least this much right away; the rest is freed when the clones are gone or macOS purges the snapshot.")
                }
            }
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
    let selectedGuaranteedBytes: Int64
    let hasIrreversibleOperations: Bool
    let isCleaning: Bool
    let isXcodeRunning: Bool
    let itemsWaitingForXcode: Int
    let clean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasIrreversibleOperations ? "exclamationmark.shield" : "trash")
                .foregroundStyle(hasIrreversibleOperations ? Color.cleanerWarning : Color.cleanerSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.subheadline.weight(.semibold))
                Text(cleanupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: clean) {
                Label(isCleaning ? "Cleaning…" : "Review & Clean", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCleaning || (isXcodeRunning && itemsWaitingForXcode == selectedCount))
            .help(isXcodeRunning && itemsWaitingForXcode == selectedCount
                ? "Quit Xcode before cleaning the selected items."
                : "Review the selected cleanup actions.")
        }
        .padding(14)
        .cleanerSubtleSurface()
    }

    private var selectionSummary: String {
        let size = ByteCountFormatter.cleanerString(from: selectedBytes)
        guard selectedGuaranteedBytes < selectedBytes else { return "\(selectedCount) selected · \(size)" }
        return "\(selectedCount) selected · \(size) (at least \(ByteCountFormatter.cleanerString(from: selectedGuaranteedBytes)) freed right away)"
    }

    private var cleanupDescription: String {
        if isXcodeRunning {
            if itemsWaitingForXcode == selectedCount {
                return "Quit Xcode to clean these items. They belong to Xcode and cannot be removed while it is open."
            }
            return itemsWaitingForXcode > 0
                ? "Xcode is open: build data and devices it is using are skipped, and \(itemsWaitingForXcode) items wait until you quit it."
                : "Xcode is open: build data and devices it is using are skipped."
        }
        return hasIrreversibleOperations
            ? "Includes Simulator or Homebrew operations that cannot be undone."
            : "Selected items will move to the Trash."
    }
}

private struct DeveloperStorageXcodeRunningBanner: View {
    var body: some View {
        Label(
            "Xcode is open. Projects and Simulators it is using are protected; other Xcode data waits until you quit it.",
            systemImage: "lock.shield.fill"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.cleanerWarning)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerSubtleSurface()
        .accessibilityLabel("Xcode is open; items it is using are protected from cleanup")
    }
}

/// Explains why cleanup frees little space right away: the data is still
/// referenced by a Time Machine local snapshot.
private struct DeveloperStorageSnapshotBanner: View {
    let heldBytes: Int64
    let snapshotDate: Date

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("A Time Machine local snapshot from \(snapshotDescription) still holds \(ByteCountFormatter.cleanerString(from: heldBytes)) of the recommended data.")
                    .font(.subheadline.weight(.medium))
                Text("Cleaning removes it now, but the space returns only when macOS releases the snapshot. macOS does this automatically when space is needed, and Time Machine replaces local snapshots within 24 hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.cleanerInfo)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerSubtleSurface()
    }

    private var snapshotDescription: String {
        Calendar.current.isDateInToday(snapshotDate)
            ? snapshotDate.formatted(date: .omitted, time: .shortened)
            : snapshotDate.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Offered after a cleanup when a local snapshot still holds removed data.
private struct DeveloperStorageSnapshotReleasePanel: View {
    let releasableBytes: Int64?
    let isReleasing: Bool
    let result: LocalSnapshotReleaseResult?
    let errorMessage: String?
    let release: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(errorMessage == nil ? Color.cleanerInfo : Color.cleanerDanger)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let releasableBytes, result == nil {
                Button(action: release) {
                    Label(isReleasing ? "Releasing…" : "Release \(ByteCountFormatter.cleanerString(from: releasableBytes))…",
                          systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(isReleasing)
                .help("Ask macOS to thin Time Machine local snapshots until this space is reclaimed.")
            }
        }
        .padding(12)
        .cleanerSubtleSurface()
    }

    private var title: String {
        if let errorMessage { return errorMessage }
        if let result {
            let freed = result.measuredFreedBytes.map { $0 > 0 ? "+\(ByteCountFormatter.cleanerString(from: $0)) free space measured" : "no measurable change in free space yet" } ?? "free space unknown"
            return "Released \(result.snapshotsRemoved) of \(result.snapshotsBefore) local snapshots · \(freed)"
        }
        return "A Time Machine local snapshot still holds the space this cleanup removed."
    }

    private var detail: String {
        if result != nil || errorMessage != nil {
            return "Backups on a Time Machine disk are not affected."
        }
        return "macOS releases it automatically when space is needed. Release it now to free the space immediately; the restore points in those snapshots are lost."
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
            VStack(alignment: .leading, spacing: 3) {
                Label(
                    "Cleanup complete: \(removed) removed · \(ByteCountFormatter.cleanerString(from: result.removedBytes))",
                    systemImage: hasWarnings ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .foregroundStyle(hasWarnings ? Color.cleanerWarning : Color.cleanerSuccess)
                if let verification {
                    Text(verification)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    /// What the volume actually reports, measured before and after the batch.
    private var verification: String? {
        var parts: [String] = []
        if let measured = result.measuredFreedBytes {
            parts.append(measured > 0
                ? "Free space measured: +\(ByteCountFormatter.cleanerString(from: measured))"
                : "No measurable change in free space yet")
        }
        if result.bytesInTrash > 0 {
            parts.append("\(ByteCountFormatter.cleanerString(from: result.bytesInTrash)) is in the Trash until you empty it")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
