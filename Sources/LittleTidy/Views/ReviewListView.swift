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
    @State private var expandedDuplicateIDs: Set<ReviewItem.ID> = []
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

                if headerStyle == .large {
                    HStack(alignment: .top, spacing: 14) {
                        reviewList
                            .frame(minWidth: 460)
                        ReviewInspectorView(item: selectedInspectorItem, store: store)
                            .frame(width: 330)
                    }
                } else {
                    reviewList
                }
            }
        }
        .onAppear {
            if headerStyle == .large, store.selectedInspectorItemID == nil {
                store.selectedInspectorItemID = filteredItems.first?.id
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
                                isInspectorSelected: store.selectedInspectorItemID == item.id,
                                isExpanded: expandedDuplicateIDs.contains(item.id),
                                toggle: {
                                    store.toggleSelection(for: item)
                                },
                                inspect: {
                                    store.selectedInspectorItemID = item.id
                                },
                                toggleExpansion: {
                                    toggleExpansion(for: item)
                                },
                                reveal: {
                                    store.revealInFinder(item)
                                },
                                open: {
                                    store.openFirstPlannedURL(item)
                                },
                                preview: {
                                    store.preview(item)
                                }
                            )

                            if expandedDuplicateIDs.contains(item.id) {
                                if !item.duplicateCopies.isEmpty {
                                    DuplicateCopiesView(item: item, store: store)
                                } else if !item.relatedData.isEmpty {
                                    RelatedDataView(item: item, store: store)
                                }
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
        guard !item.duplicateCopies.isEmpty || !item.relatedData.isEmpty else {
            return
        }
        if expandedDuplicateIDs.contains(item.id) {
            expandedDuplicateIDs.remove(item.id)
        } else {
            expandedDuplicateIDs.insert(item.id)
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

    private var selectedInspectorItem: ReviewItem? {
        guard let id = store.selectedInspectorItemID else {
            return filteredItems.first
        }
        return filteredItems.first { $0.id == id } ?? filteredItems.first
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
                    Label("Cache Review Required", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Caches are regenerable, but they can dominate cleanup size. Review this category before selecting cache items.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectReviewedCaches()
                } label: {
                    Label("Select Reviewed Caches", systemImage: "checkmark.circle")
                }
                .buttonStyle(.glass)
                .disabled(!preview.hasItems)
            }

            HStack(spacing: 18) {
                CacheMetric(label: "Items", value: "\(preview.itemCount)")
                CacheMetric(label: "Entries", value: "\(preview.filesystemEntryCount)")
                CacheMetric(label: "Reclaimable", value: ByteCountFormatter.cleanerString(from: preview.bytes))
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
                HStack(spacing: 8) {
                    Label("Search", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $store.reviewSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 320)
                }

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
    }

    private var filterControls: some View {
        HStack(spacing: 12) {
            Label("Search", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)

            TextField("Search", text: $store.reviewSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 320)

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
}

private struct ReviewBatchToolbar: View {
    @ObservedObject var store: ScanReviewStore
    let visibleItems: [ReviewItem]
    let category: CleanupCategory?
    let selectReviewedCaches: () -> Void

    private var visibleHighConfidenceCount: Int {
        visibleItems.filter { $0.confidence == .high && $0.category != .cache }.count
    }

    private var visibleCacheCount: Int {
        visibleItems.filter { $0.category == .cache && $0.confidence == .high }.count
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
                store.selectHighConfidence(in: visibleItems)
            } label: {
                Label("Select High Confidence", systemImage: "checkmark.seal")
            }
            .disabled(visibleHighConfidenceCount == 0)

            Button {
                if category == .cache {
                    selectReviewedCaches()
                } else {
                    store.selectVisibleReviewedItems(visibleItems)
                }
            } label: {
                Label("Select Visible", systemImage: "checkmark.circle")
            }
            .disabled(category == .cache ? visibleCacheCount == 0 : visibleHighConfidenceCount == 0)

            Button {
                store.deselectVisibleItems(visibleItems)
            } label: {
                Label("Deselect Visible", systemImage: "minus.circle")
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
        Text("\(visibleItems.count) visible · \(store.visibleSelectedCount(from: visibleItems)) selected · \(ByteCountFormatter.cleanerString(from: store.visibleSelectedBytes(from: visibleItems))) selected")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ReviewRow: View {
    let item: ReviewItem
    let isSelected: Bool
    let isInspectorSelected: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let inspect: () -> Void
    let toggleExpansion: () -> Void
    let reveal: () -> Void
    let open: () -> Void
    let preview: () -> Void

    private var hasExpandableDetail: Bool {
        !item.duplicateCopies.isEmpty || !item.relatedData.isEmpty
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: toggleExpansion) {
                Image(systemName: hasExpandableDetail ? (isExpanded ? "chevron.down" : "chevron.right") : "circle")
                    .foregroundStyle(hasExpandableDetail ? Color.secondary : Color.clear)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasExpandableDetail)
            .accessibilityLabel(isExpanded ? "Collapse details for \(item.title)" : "Expand details for \(item.title)")
            .help(hasExpandableDetail ? "Show item details" : "")

            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
                .frame(width: 44, alignment: .center)
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
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    RiskChip(risk: ReviewRisk.risk(for: item.confidence))
                }
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
                ConfidenceBadge(confidence: item.confidence)
            }
            .frame(minWidth: 120, alignment: .trailing)

            Menu {
                Button("Preview", action: preview)
                Button("Reveal in Finder", action: reveal)
                Button("Open", action: open)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions for \(item.title)")
        }
        .padding(14)
        .background {
            if isInspectorSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: inspect)
        .contextMenu {
            Button("Preview", action: preview)
            Button("Reveal in Finder", action: reveal)
            Button("Open", action: open)
        }
    }
}

private struct RiskChip: View {
    let risk: ReviewRisk

    var body: some View {
        Label(risk.title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var symbol: String {
        switch risk {
        case .low:
            return "checkmark.shield"
        case .review:
            return "exclamationmark.triangle"
        case .careful:
            return "questionmark.diamond"
        }
    }

    private var color: Color {
        switch risk {
        case .low:
            return .cleanerSuccess
        case .review:
            return .cleanerWarning
        case .careful:
            return .cleanerDanger
        }
    }
}

private struct DuplicateCopiesView: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(item.duplicateCopies) { copy in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { copy.isSelected },
                        set: { _ in store.toggleDuplicateCopy(for: item, copy: copy) }
                    ))
                    .labelsHidden()
                    .disabled(copy.isRecommendedKeep)
                    .accessibilityLabel(copy.isRecommendedKeep ? "Keep \(copy.url.lastPathComponent)" : (copy.isSelected ? "Deselect \(copy.url.lastPathComponent)" : "Select \(copy.url.lastPathComponent)"))
                    .accessibilityHint(copy.isRecommendedKeep ? "Recommended copy to keep; duplicate rules prevent selecting every copy." : "Adds this duplicate copy to the cleanup plan.")

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
                        Button("Reveal in Finder") {
                            store.revealInFinder(copy)
                        }
                        Button("Preview") {
                            store.preview(copy)
                        }
                        Button("Open") {
                            store.open(copy)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More actions for \(copy.url.lastPathComponent)")
                }
                .padding(.vertical, 8)
                .padding(.leading, 58)
                .padding(.trailing, 14)
            }
        }
        .cleanerSubtleSurface(cornerRadius: 0)
    }
}

private struct RelatedDataView: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    private var totalBytes: Int64 {
        item.relatedData.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle("Also remove related data", isOn: $store.includeRelatedAppData)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Text("\(item.relatedData.count) items · \(ByteCountFormatter.cleanerString(from: totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.leading, 58)
            .padding(.trailing, 14)

            Text(store.includeRelatedAppData
                 ? "Matched by bundle identifier. Included in the cleanup plan and moved to Trash with the app."
                 : "Matched by bundle identifier. Not included — enable the switch to move these to Trash with the app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 58)
                .padding(.trailing, 14)
                .padding(.bottom, 6)

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
                .padding(.vertical, 8)
                .padding(.leading, 58)
                .padding(.trailing, 14)
                .opacity(store.includeRelatedAppData ? 1 : 0.55)
            }
        }
        .cleanerSubtleSurface(cornerRadius: 0)
    }
}

private struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Label(confidence.rawValue.capitalized, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(foregroundStyle)
    }

    private var symbol: String {
        switch confidence {
        case .high: "checkmark.seal"
        case .medium: "exclamationmark.triangle"
        case .low: "questionmark.circle"
        }
    }

    private var foregroundStyle: Color {
        switch confidence {
        case .high: .cleanerSuccess
        case .medium: .cleanerWarning
        case .low: .secondary
        }
    }
}

private struct ReviewInspectorView: View {
    let item: ReviewItem?
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inspector")
                            .font(.headline)
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer()
                    ConfidenceBadge(confidence: item.confidence)
                }

                InspectorMetricGrid(item: item, store: store)

                InspectorSection(title: "Recommendation", systemImage: "checkmark.seal") {
                    Text(item.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(ReviewRisk.risk(for: item.confidence).title, systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(riskColor(for: item))
                }

                categoryProof(for: item)

                InspectorSection(title: "Planned Trash Entries", systemImage: "trash") {
                    let plannedURLs = store.plannedURLs(for: item)
                    if plannedURLs.isEmpty {
                        Text("Select this item to add entries to the cleanup plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(plannedURLs.prefix(6)), id: \.self) { url in
                            Text(url.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if plannedURLs.count > 6 {
                            Text("\(plannedURLs.count - 6) more entries")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                InspectorSection(title: "Recovery", systemImage: "arrow.uturn.backward.circle") {
                    Text("Cleanup moves items to Trash. Nothing is permanently deleted by LittleTidy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        store.preview(item)
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    Button {
                        store.revealInFinder(item)
                    } label: {
                        Label("Reveal", systemImage: "magnifyingglass")
                    }
                    Button {
                        store.openFirstPlannedURL(item)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
                    }
                }
                .controlSize(.small)
            } else {
                ContentUnavailableView(
                    "No Item Selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a review row to inspect recommendation evidence.")
                )
            }
        }
        .padding(16)
        .cleanerSurface()
    }

    @ViewBuilder
    private func categoryProof(for item: ReviewItem) -> some View {
        switch item.category {
        case .duplicate:
            InspectorSection(title: "Duplicate Proof", systemImage: "doc.on.doc") {
                Text("Same size and SHA-256 hash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hash = item.contentHash {
                    Text(hash)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ForEach(item.duplicateCopies) { copy in
                    Label(copy.isRecommendedKeep ? "Keep \(copy.url.lastPathComponent)" : (copy.isSelected ? "Trash \(copy.url.lastPathComponent)" : "Candidate \(copy.url.lastPathComponent)"), systemImage: copy.isRecommendedKeep ? "checkmark.shield" : "doc")
                        .font(.caption)
                        .foregroundStyle(copy.isRecommendedKeep ? Color.cleanerSuccess : Color.secondary)
                }
            }
        case .largeFile:
            InspectorSection(title: "Large File Evidence", systemImage: "externaldrive") {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.location)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .unusedApp:
            InspectorSection(title: "App Evidence", systemImage: "app.badge") {
                if let bundleIdentifier = item.bundleIdentifier {
                    Label(bundleIdentifier, systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastOpenedDate = item.lastOpenedDate {
                    Label("Last opened \(lastOpenedDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let installDate = item.installDate {
                    Label("Installed \(installDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(store.includeRelatedAppData ? "Related app data included" : "Related app data excluded", systemImage: store.includeRelatedAppData ? "folder.badge.minus" : "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.includeRelatedAppData ? Color.cleanerWarning : Color.secondary)
                ForEach(item.relatedData.prefix(5), id: \.url) { entry in
                    Text("\(entry.kind): \(entry.url.lastPathComponent) · \(ByteCountFormatter.cleanerString(from: entry.sizeBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .cache:
            InspectorSection(title: "Cache Evidence", systemImage: "shippingbox") {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Regenerable cache. Review before selecting because caches can dominate cleanup size.")
                    .font(.caption)
                    .foregroundStyle(Color.cleanerWarning)
            }
        }
    }

    private func riskColor(for item: ReviewItem) -> Color {
        switch ReviewRisk.risk(for: item.confidence) {
        case .low:
            return .cleanerSuccess
        case .review:
            return .cleanerWarning
        case .careful:
            return .cleanerDanger
        }
    }
}

private struct InspectorMetricGrid: View {
    let item: ReviewItem
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                metric("Category", item.category.displayTitle)
                metric("Size", ByteCountFormatter.cleanerString(from: item.bytes))
            }
            GridRow {
                metric("Selected", "\(store.selectedEntryCount(for: item)) entries")
                metric("Risk", ReviewRisk.risk(for: item.confidence).title)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .cleanerSubtleSurface(cornerRadius: 10)
    }
}
