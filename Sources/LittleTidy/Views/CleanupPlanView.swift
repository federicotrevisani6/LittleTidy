import LittleTidyCore
import SwiftUI

struct CleanupPlanView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingCleanupConfirmation = false

    var body: some View {
        let validation = store.cleanupPlanValidation

        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 16) {
                CleanupPlanSummaryPanel(
                    store: store,
                    validation: validation,
                    moveToTrash: {
                        if store.validateCleanupPlan() != nil {
                            store.manualReviewConfirmed = !store.selectedNeedsManualReview
                            showingCleanupConfirmation = true
                        }
                    }
                )
                .sheet(isPresented: $showingCleanupConfirmation) {
                    CleanupConfirmationSheet(
                        store: store,
                        message: cleanupConfirmationMessage,
                        confirm: {
                            showingCleanupConfirmation = false
                            store.executeCleanup()
                        },
                        cancel: {
                            showingCleanupConfirmation = false
                        }
                    )
                    .frame(minWidth: 520)
                    .padding(22)
                }

            if let cleanupErrorMessage = store.cleanupErrorMessage {
                Label(cleanupErrorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.cleanerWarning)
                    .padding(12)
                    .cleanerSubtleSurface()
            }

            if let cleanupResultMessage = store.cleanupResultMessage {
                Label(cleanupResultMessage, systemImage: "checkmark.circle")
                    .foregroundStyle(Color.cleanerSuccess)
                    .padding(12)
                    .cleanerSubtleSurface()
            }

            CleanupReportView(store: store, items: store.filteredCleanupReportItems())

            CleanupCategoryGroupsView(items: store.selectedItems, store: store)

            CleanupHistoryView(store: store)
            }
        }
    }

    private var cleanupConfirmationMessage: String {
        var lines = [
            "\(store.selectedFilesystemEntryCount) filesystem entries, \(ByteCountFormatter.cleanerString(from: store.selectedBytes)), will be moved to Trash.",
            "This does not permanently delete them.",
            "System folders are excluded."
        ]

        let breakdown = store.selectedCategoryBreakdown
        if !breakdown.isEmpty {
            lines.append("")
            lines.append(contentsOf: breakdown.map { category, count, bytes in
                "\(category.displayTitle): \(count) items, \(ByteCountFormatter.cleanerString(from: bytes))"
            })
        }

        let riskBreakdown = store.selectedRiskBreakdown
        if !riskBreakdown.isEmpty {
            lines.append("")
            lines.append(contentsOf: riskBreakdown.map { risk, count, bytes in
                "\(risk.title): \(count) items, \(ByteCountFormatter.cleanerString(from: bytes))"
            })
        }

        return lines.joined(separator: "\n")
    }
}

private struct CleanupConfirmationSheet: View {
    @ObservedObject var store: ScanReviewStore
    let message: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(Color.cleanerWarning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move selected items to Trash?")
                        .font(.title2.weight(.semibold))
                    Text("LittleTidy moves files to Trash only. You can still recover them from Finder.")
                        .foregroundStyle(.secondary)
                }
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .cleanerSubtleSurface()

            CleanupBreakdownPanel(store: store)

            if store.selectedNeedsManualReview {
                Toggle(isOn: $store.manualReviewConfirmed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I manually reviewed the non-high-confidence items")
                            .font(.subheadline.weight(.semibold))
                        Text("Medium and low confidence items are never selected by bulk actions, so confirm that you inspected them before cleanup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button(role: .destructive, action: confirm) {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(store.selectedNeedsManualReview && !store.manualReviewConfirmed)
                .buttonStyle(.glassProminent)
            }
        }
    }
}

private struct CleanupBreakdownPanel: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plan Breakdown", systemImage: "list.bullet.rectangle")
                .font(.headline)

            ForEach(store.selectedCategoryBreakdown, id: \.0) { category, count, bytes in
                HStack {
                    Text(category.displayTitle)
                    Spacer()
                    Text("\(count) items")
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.cleanerString(from: bytes))
                        .monospacedDigit()
                }
                .font(.caption)
            }

            Divider()

            ForEach(store.selectedRiskBreakdown, id: \.0) { risk, count, bytes in
                HStack {
                    Text(risk.title)
                    Spacer()
                    Text("\(count) items")
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.cleanerString(from: bytes))
                        .monospacedDigit()
                }
                .font(.caption)
            }

            Label(store.includeRelatedAppData ? "Matched related app data is included." : "Related app data is excluded unless deep uninstall is enabled.", systemImage: "folder.badge.gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}

private struct CleanupPlanSummaryPanel: View {
    @ObservedObject var store: ScanReviewStore
    let validation: CleanupPlanValidation
    let moveToTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup Plan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Final review before moving anything to Trash.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: moveToTrash) {
                    Label(store.isCleaning ? "Cleaning" : "Move Selected to Trash", systemImage: "trash")
                }
                .disabled(!validation.canMoveToTrash)
                .buttonStyle(.glassProminent)
                .accessibilityHint("Opens the final Trash confirmation before moving selected items.")
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(store.selectedItems.count) items selected", systemImage: "checkmark.circle")
                    Label("\(store.selectedFilesystemEntryCount) filesystem entries planned", systemImage: "doc.badge.gearshape")
                    Label(ByteCountFormatter.cleanerString(from: store.selectedBytes), systemImage: "externaldrive.badge.minus")
                    Label(appSupportDataSummary, systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label(validation.title, systemImage: iconName)
                        .font(.headline)
                        .foregroundStyle(iconColor)

                    Text(validation.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(validation.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .cleanerSurface()
    }

    private var iconName: String {
        switch validation.state {
        case .noSelection:
            return "checkmark.circle"
        case .ready:
            return "checkmark.seal"
        case .blocked:
            return "xmark.octagon"
        }
    }

    private var iconColor: Color {
        switch validation.state {
        case .noSelection:
            return .secondary
        case .ready:
            return .cleanerSuccess
        case .blocked:
            return .cleanerWarning
        }
    }

    private var appSupportDataSummary: String {
        if store.selectedItems.contains(where: { $0.category == .unusedApp }) {
            return store.includeRelatedAppData ? "Matched app support data is included." : "Matched app support data is excluded."
        }
        return "System folders are excluded."
    }
}

private struct CleanupCategoryGroupsView: View {
    let items: [ReviewItem]
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected Items")
                    .font(.largeTitle.weight(.semibold))
                Text("Items are grouped by cleanup category before plan validation.")
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No Items Selected",
                    systemImage: "checkmark.circle",
                    description: Text("Select duplicates, large files, or unused apps to build a cleanup plan.")
                )
                .frame(maxWidth: .infinity)
                .padding(24)
                .cleanerSurface()
            } else {
                ForEach(categoryGroups, id: \.category) { group in
                    ReviewListView(
                        title: group.title,
                        subtitle: "\(group.items.count) selected, \(ByteCountFormatter.cleanerString(from: store.selectedBytes(for: group.category)))",
                        items: store.sortedItems(group.items),
                        category: group.category,
                        store: store,
                        headerStyle: .section
                    )
                }
            }
        }
    }

    private var categoryGroups: [CleanupCategoryGroup] {
        CleanupCategoryGroup.orderedCategories.compactMap { category in
            let categoryItems = items.filter { $0.category == category }
            guard !categoryItems.isEmpty else {
                return nil
            }
            return CleanupCategoryGroup(category: category, items: categoryItems)
        }
    }
}

private struct CleanupCategoryGroup {
    static let orderedCategories: [CleanupCategory] = [.duplicate, .largeFile, .unusedApp, .cache]

    let category: CleanupCategory
    let items: [ReviewItem]

    var title: String {
        switch category {
        case .duplicate:
            return "Duplicates"
        case .largeFile:
            return "Large Files"
        case .unusedApp:
            return "Unused Apps"
        case .cache:
            return "Caches"
        }
    }

}

private struct CleanupHistoryView: View {
    @ObservedObject var store: ScanReviewStore

    private var totalFreed: Int64 {
        store.cleanupHistory.reduce(Int64(0)) { $0 + $1.bytesFreed }
    }

    var body: some View {
        if !store.cleanupHistory.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.cleanupHistory.prefix(10)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline.weight(.medium))
                                Text(historyDetail(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(ByteCountFormatter.cleanerString(from: entry.bytesFreed))
                                .font(.headline)
                                .foregroundStyle(Color.cleanerSuccess)
                        }
                    }

                    if store.cleanupHistory.count > 10 {
                        Text("\(store.cleanupHistory.count - 10) earlier cleanups not shown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear History", role: .destructive) {
                        store.clearCleanupHistory()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Label("Cleanup History", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    Text("\(ByteCountFormatter.cleanerString(from: totalFreed)) freed total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .cleanerSurface()
        }
    }

    private func historyDetail(for entry: CleanupHistoryEntry) -> String {
        var parts = ["\(entry.movedCount) moved"]
        if entry.skippedCount > 0 {
            parts.append("\(entry.skippedCount) skipped")
        }
        if entry.failedCount > 0 {
            parts.append("\(entry.failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }
}

private struct CleanupReportView: View {
    @ObservedObject var store: ScanReviewStore
    let items: [CleanupReportItem]

    private var failedCount: Int {
        items.filter { $0.status == .failed }.count
    }

    var body: some View {
        if !store.cleanupReportItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Cleanup Report", systemImage: "list.bullet.clipboard")
                        .font(.headline)
                    Spacer()
                    Picker("Report Filter", selection: $store.cleanupReportFilter) {
                        ForEach(CleanupReportFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 280)
                    Button {
                        store.startOrCancelScan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isScanning)
                    Button {
                        store.openTrash()
                    } label: {
                        Label("Open Trash", systemImage: "trash")
                    }
                    if failedCount > 0 {
                        Button {
                            store.retryFailedCleanup()
                        } label: {
                            Label("Retry Failed", systemImage: "arrow.clockwise")
                        }
                    }
                }

                if items.isEmpty {
                    ContentUnavailableView(
                        "No Report Items",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Choose another report filter to see cleanup entries.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(18)
                } else {
                    ForEach(items) { item in
                        CleanupReportRow(item: item, store: store)
                    }
                }
            }
            .padding(16)
            .cleanerSurface()
        }
    }
}

private struct CleanupReportRow: View {
    let item: CleanupReportItem
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.status.rawValue)
                        .font(.subheadline.weight(.semibold))
                    if let category = item.category {
                        Text(category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.cleanerString(from: item.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.sourceURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let destinationURL = item.destinationURL {
                    Text(destinationURL.path(percentEncoded: false))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(item.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if item.status != .moved {
                    Text(item.message)
                        .font(.caption2)
                        .foregroundStyle(item.status == .failed ? Color.cleanerWarning : Color.secondary)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .trailing, spacing: 6) {
                if item.status == .moved, let destinationURL = item.destinationURL {
                    Button {
                        store.revealInFinder(forURL: destinationURL)
                    } label: {
                        Label("Reveal in Trash", systemImage: "magnifyingglass")
                    }
                } else {
                    Button {
                        store.revealInFinder(forURL: item.sourceURL)
                    } label: {
                        Label(item.status == .failed ? "Reveal Source" : "Reveal", systemImage: "magnifyingglass")
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var iconName: String {
        switch item.status {
        case .moved:
            return "checkmark.circle"
        case .skipped:
            return "minus.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .moved:
            return .cleanerSuccess
        case .skipped:
            return .secondary
        case .failed:
            return .cleanerWarning
        }
    }
}
