import LittleTidyCore
import SwiftUI

struct CleanupPlanView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingCleanupConfirmation = false

    var body: some View {
        let validation = store.cleanupPlanValidation

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup Plan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Final review before moving anything to Trash.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if store.validateCleanupPlan() != nil {
                        showingCleanupConfirmation = true
                    }
                } label: {
                    Label(store.isCleaning ? "Cleaning" : "Move Selected to Trash", systemImage: "trash")
                }
                .disabled(!validation.canMoveToTrash)
                .buttonStyle(.borderedProminent)
            }
            .confirmationDialog(
                "Move selected items to Trash?",
                isPresented: $showingCleanupConfirmation,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    store.executeCleanup()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(store.selectedFilesystemEntryCount) filesystem entries will be moved to Trash. This does not permanently delete them.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("\(store.selectedItems.count) items selected", systemImage: "checkmark.circle")
                Label("\(store.selectedFilesystemEntryCount) filesystem entries planned", systemImage: "doc.badge.gearshape")
                Label(ByteCountFormatter.cleanerString(from: store.selectedBytes), systemImage: "externaldrive.badge.minus")
                Label("System folders and app support data are excluded.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .cleanerSurface()

            CleanupPlanValidationView(validation: validation)

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

            CleanupReportView(items: store.cleanupReportItems)

            CleanupCategoryGroupsView(items: store.selectedItems, store: store)

            CleanupHistoryView(store: store)
        }
    }
}

private struct CleanupPlanValidationView: View {
    let validation: CleanupPlanValidation

    var body: some View {
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
        .padding(16)
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
                        subtitle: "\(group.items.count) selected, \(ByteCountFormatter.cleanerString(from: group.bytes))",
                        items: store.sortedItems(group.items),
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

    var bytes: Int64 {
        items.reduce(0) { partialResult, item in
            partialResult + selectedBytes(for: item)
        }
    }

    private func selectedBytes(for item: ReviewItem) -> Int64 {
        guard !item.duplicateCopies.isEmpty else {
            return item.bytes
        }
        return item.duplicateCopies
            .filter { $0.isSelected && !$0.isRecommendedKeep }
            .reduce(Int64(0)) { $0 + $1.bytes }
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
    let items: [CleanupReportItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Cleanup Report", systemImage: "list.bullet.clipboard")
                    .font(.headline)

                ForEach(items) { item in
                    CleanupReportRow(item: item)
                }
            }
            .padding(16)
            .cleanerSurface()
        }
    }
}

private struct CleanupReportRow: View {
    let item: CleanupReportItem

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
                } else {
                    Text(item.message)
                        .font(.caption2)
                        .foregroundStyle(item.status == .failed ? Color.cleanerWarning : Color.secondary)
                        .lineLimit(2)
                }
            }
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
