import AppKit
import LittleTidyCore
import SwiftUI

struct ReviewListView: View {
    enum HeaderStyle {
        case large
        case section
    }

    let title: String
    let subtitle: String
    let items: [ReviewItem]
    var category: CleanupCategory?
    @ObservedObject var store: ScanReviewStore
    var headerStyle: HeaderStyle = .large
    @State private var expandedIDs: Set<ReviewItem.ID> = []
    @State private var showingCacheSelectionConfirmation = false

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(titleFont)
                        Spacer()
                        if headerStyle == .large {
                            ReviewSelectionSummary(store: store)
                            SortPicker(store: store)
                        }
                    }
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .font(headerStyle == .large ? .body : .subheadline)
                }

                if headerStyle == .large {
                    ReviewFilterBar(store: store)
                    ReviewBatchToolbar(
                        store: store,
                        visibleItems: filteredItems,
                        category: category,
                        selectReviewedCaches: {
                            showingCacheSelectionConfirmation = true
                        }
                    )
                }

                if headerStyle == .large, category == .cache {
                    CacheReviewPanel(store: store, items: filteredItems) {
                        showingCacheSelectionConfirmation = true
                    }
                }

                reviewList
            }
        }
        .confirmationDialog(
            "Select reviewed caches?",
            isPresented: $showingCacheSelectionConfirmation,
            titleVisibility: .visible
        ) {
            let visibleCacheItems = filteredItems.filter { $0.category == .cache }
            Button("Select \(visibleCacheItems.count) Visible Cache Items") {
                store.selectVisibleReviewedItems(visibleCacheItems, includeCaches: true)
            }
            .disabled(visibleCacheItems.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            let visibleCacheItems = filteredItems.filter { $0.category == .cache }
            let bytes = visibleCacheItems.reduce(Int64(0)) { $0 + $1.bytes }
            Text("\(visibleCacheItems.count) visible cache items, \(ByteCountFormatter.cleanerString(from: bytes)) will be selected. Nothing moves to Trash until you confirm the Cleanup Plan.")
        }
    }

    private var reviewList: some View {
        Group {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(24)
                .cleanerSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        VStack(spacing: 0) {
                            ReviewRow(
                                item: item,
                                isSelected: item.isSelected,
                                isExpanded: expandedIDs.contains(item.id),
                                toggle: { store.toggleSelection(for: item) },
                                toggleExpansion: { toggleExpansion(for: item) }
                            )

                            if expandedIDs.contains(item.id) {
                                ReviewRowDetail(item: item, store: store)
                            }
                        }
                        if item.id != filteredItems.last?.id {
                            Divider()
                        }
                    }
                }
                .cleanerSurface()
            }
        }
    }

    private var titleFont: Font {
        switch headerStyle {
        case .large:
            return .largeTitle.weight(.semibold)
        case .section:
            return .title3.weight(.semibold)
        }
    }

    private func toggleExpansion(for item: ReviewItem) {
        if expandedIDs.contains(item.id) {
            expandedIDs.remove(item.id)
        } else {
            expandedIDs.insert(item.id)
        }
    }

    private var filteredItems: [ReviewItem] {
        guard headerStyle == .large else {
            return items
        }
        return store.visibleReviewItems(from: items)
    }

    private var hasActiveFilter: Bool {
        headerStyle == .large && (store.reviewFilterScope != .all || !store.reviewSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var emptyTitle: String {
        hasActiveFilter ? "No Matching Items" : "No Items Found"
    }

    private var emptyDescription: String {
        hasActiveFilter ? "Adjust search or filter scope to show more results." : "Run a scan or choose another category."
    }
}

private struct ReviewSelectionSummary: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.cleanerString(from: store.selectedBytes))
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected total \(ByteCountFormatter.cleanerString(from: store.selectedBytes))")
    }
}

private struct CacheReviewPanel: View {
    @ObservedObject var store: ScanReviewStore
    let items: [ReviewItem]
    let selectReviewedCaches: () -> Void

    private var preview: BulkSelectionPreview {
        store.reviewedCachesSelectionPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Review caches before selecting", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Caches are safe to remove and rebuild automatically, but they can dominate cleanup size. Skim them before adding to the plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectReviewedCaches()
                } label: {
                    Label("Select Caches", systemImage: "checkmark.circle")
                }
                .buttonStyle(.glass)
                .disabled(!preview.hasItems)
            }

            HStack(spacing: 18) {
                CacheMetric(label: "Groups", value: "\(preview.itemCount)")
                CacheMetric(label: "Files & folders", value: "\(preview.filesystemEntryCount)")
                CacheMetric(label: "Can be freed", value: ByteCountFormatter.cleanerString(from: preview.bytes))
            }

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Largest cache groups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(items.prefix(3))) { item in
                        HStack {
                            Text(item.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(ByteCountFormatter.cleanerString(from: item.bytes))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .cleanerSurface()
    }
}

private struct CacheMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}

private struct SortPicker: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Picker("Sort", selection: $store.reviewSortOption) {
            ForEach(ReviewSortOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: 420)
    }
}

private struct ReviewFilterBar: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterControls

            VStack(alignment: .leading, spacing: 8) {
                searchField
                scopePicker
            }
        }
    }

    private var filterControls: some View {
        HStack(spacing: 12) {
            searchField
            scopePicker
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Label("Search", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            TextField("Search", text: $store.reviewSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 320)
        }
    }

    private var scopePicker: some View {
        Picker("Filter", selection: $store.reviewFilterScope) {
            ForEach(ReviewFilterScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(minWidth: 220, maxWidth: 260)
    }
}

private struct ReviewBatchToolbar: View {
    @ObservedObject var store: ScanReviewStore
    let visibleItems: [ReviewItem]
    let category: CleanupCategory?
    let selectReviewedCaches: () -> Void

    private var visibleSafeCount: Int {
        visibleItems.filter { $0.confidence == .high && $0.category != .cache }.count
    }

    private var visibleCacheCount: Int {
        visibleItems.filter { $0.category == .cache && $0.confidence == .high }.count
    }

    private var canSelectSafe: Bool {
        category == .cache ? visibleCacheCount > 0 : visibleSafeCount > 0
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls
            VStack(alignment: .leading, spacing: 8) {
                controls
                summary
            }
        }
        .padding(12)
        .cleanerSubtleSurface()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            summary
            Spacer()
            Button {
                if category == .cache {
                    selectReviewedCaches()
                } else {
                    store.selectHighConfidence(in: visibleItems)
                }
            } label: {
                Label("Select Safe", systemImage: "checkmark.seal")
            }
            .disabled(!canSelectSafe)
            .help("Selects the high-confidence items shown here.")

            Button {
                store.deselectVisibleItems(visibleItems)
            } label: {
                Label("Deselect Shown", systemImage: "minus.circle")
            }
            .disabled(visibleItems.isEmpty)

            Button {
                store.undoBulkSelection()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.bulkSelectionUndoMessage == nil)
        }
        .controlSize(.small)
    }

    private var summary: some View {
        Text("\(visibleItems.count) shown · \(store.visibleSelectedCount(from: visibleItems)) selected · \(ByteCountFormatter.cleanerString(from: store.visibleSelectedBytes(from: visibleItems)))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ReviewRow: View {
    let item: ReviewItem
    let isSelected: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let toggleExpansion: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
                .frame(width: 36, alignment: .center)
                .accessibilityLabel(isSelected ? "Deselect \(item.title)" : "Select \(item.title)")
                .accessibilityHint("Adds or removes this item from the cleanup plan.")
                .help(isSelected ? "Remove from cleanup plan" : "Add to cleanup plan")

            Divider()
                .frame(height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                SafetyChip(risk: ReviewRisk.risk(for: item.confidence))
            }
            .layoutPriority(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.cleanerString(from: item.bytes))
                    .font(.headline)
                Text(item.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 120, alignment: .trailing)

            Button(action: toggleExpansion) {
                Label(isExpanded ? "Hide details" : "Show details", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "Hide details for \(item.title)" : "Show details for \(item.title)")
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpansion)
    }
}

/// Detail panel revealed when a review row is expanded. Replaces the former
/// side inspector — evidence, planned Trash entries, and per-item actions now
/// live inline with the row they describe.
private struct ReviewRowDetail: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(ReviewRisk.risk(for: item.confidence).explanation, systemImage: ReviewRisk.risk(for: item.confidence).systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(riskColor)

            evidence

            if !item.duplicateCopies.isEmpty {
                DuplicateCopiesView(item: item, store: store)
            } else if !item.relatedData.isEmpty {
                RelatedDataView(item: item, store: store)
            }

            plannedEntries

            HStack(spacing: 10) {
                Button {
                    store.preview(item)
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                Button {
                    store.revealInFinder(item)
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                Button {
                    store.openFirstPlannedURL(item)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }

    private var riskColor: Color {
        switch ReviewRisk.risk(for: item.confidence) {
        case .low: .cleanerSuccess
        case .review: .cleanerWarning
        case .careful: .cleanerDanger
        }
    }

    @ViewBuilder
    private var evidence: some View {
        switch item.category {
        case .duplicate:
            if let hash = item.contentHash {
                DetailLine(label: "Match", value: "Same size and SHA-256 hash", mono: hash)
            }
        case .largeFile:
            DetailLine(label: "Location", value: item.location, mono: nil)
        case .unusedApp:
            VStack(alignment: .leading, spacing: 4) {
                if let bundleIdentifier = item.bundleIdentifier {
                    DetailLine(label: "Bundle", value: bundleIdentifier, mono: nil)
                }
                if let lastOpenedDate = item.lastOpenedDate {
                    DetailLine(label: "Last opened", value: lastOpenedDate.formatted(date: .abbreviated, time: .omitted), mono: nil)
                }
                Text(store.includeRelatedAppData ? "Related app data is included with this app." : "Related app data stays unless deep uninstall is on.")
                    .font(.caption)
                    .foregroundStyle(store.includeRelatedAppData ? Color.cleanerWarning : .secondary)
            }
        case .cache:
            Text("Regenerable cache. macOS and apps rebuild this automatically as needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var plannedEntries: some View {
        let plannedURLs = store.plannedURLs(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            Label("Moves to Trash", systemImage: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if plannedURLs.isEmpty {
                Text("Select this item to add it to the cleanup plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(plannedURLs.prefix(6)), id: \.self) { url in
                    Text(url.path(percentEncoded: false))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if plannedURLs.count > 6 {
                    Text("\(plannedURLs.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String
    let mono: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let mono {
                Text(mono)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct SafetyChip: View {
    let risk: ReviewRisk

    var body: some View {
        Label(risk.title, systemImage: risk.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .help(risk.explanation)
    }

    private var color: Color {
        switch risk {
        case .low: .cleanerSuccess
        case .review: .cleanerWarning
        case .careful: .cleanerDanger
        }
    }
}

private struct DuplicateCopiesView: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(item.duplicateCopies) { copy in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { copy.isSelected },
                        set: { _ in store.toggleDuplicateCopy(for: item, copy: copy) }
                    ))
                    .labelsHidden()
                    .disabled(copy.isRecommendedKeep)
                    .accessibilityLabel(copy.isRecommendedKeep ? "Keep \(copy.url.lastPathComponent)" : (copy.isSelected ? "Deselect \(copy.url.lastPathComponent)" : "Select \(copy.url.lastPathComponent)"))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(copy.url.lastPathComponent)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if copy.isRecommendedKeep {
                                Label("Keep", systemImage: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(Color.cleanerSuccess)
                            } else {
                                Label(copy.isSelected ? "Move to Trash" : "Candidate", systemImage: copy.isSelected ? "trash" : "circle.dashed")
                                    .font(.caption)
                                    .foregroundStyle(copy.isSelected ? Color.cleanerWarning : Color.secondary)
                            }
                        }
                        Text(copy.url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .layoutPriority(1)

                    Spacer()

                    Text(ByteCountFormatter.cleanerString(from: copy.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        Button("Reveal in Finder") { store.revealInFinder(copy) }
                        Button("Preview") { store.preview(copy) }
                        Button("Open") { store.open(copy) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More actions for \(copy.url.lastPathComponent)")
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.leading, 8)
    }
}

private struct RelatedDataView: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    private var totalBytes: Int64 {
        item.relatedData.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Also remove related data", isOn: $store.includeRelatedAppData)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Text("\(item.relatedData.count) items · \(ByteCountFormatter.cleanerString(from: totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(store.includeRelatedAppData
                 ? "Matched by bundle identifier. Included in the plan and moved to Trash with the app."
                 : "Matched by bundle identifier. Turn on the switch to move these with the app.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(item.relatedData, id: \.url) { entry in
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(entry.kind)
                                .font(.subheadline.weight(.medium))
                            Text(entry.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(entry.url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .layoutPriority(1)

                    Spacer()

                    Text(ByteCountFormatter.cleanerString(from: entry.sizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        store.revealInFinder(forURL: entry.url)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .opacity(store.includeRelatedAppData ? 1 : 0.55)
            }
        }
        .padding(.leading, 8)
    }
}
