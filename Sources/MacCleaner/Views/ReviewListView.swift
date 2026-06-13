import AppKit
import MacCleanerCore
import SwiftUI

struct ReviewListView: View {
    enum HeaderStyle {
        case large
        case section
    }

    let title: String
    let subtitle: String
    let items: [ReviewItem]
    @ObservedObject var store: ScanReviewStore
    var headerStyle: HeaderStyle = .large
    @State private var expandedDuplicateIDs: Set<ReviewItem.ID> = []
    @State private var searchText = ""
    @State private var filterScope: ReviewFilterScope = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(titleFont)
                    Spacer()
                    if headerStyle == .large {
                        SortPicker(store: store)
                    }
                }
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(headerStyle == .large ? .body : .subheadline)
            }

            if headerStyle == .large {
                ReviewFilterBar(searchText: $searchText, filterScope: $filterScope)
            }

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
                                isExpanded: expandedDuplicateIDs.contains(item.id),
                                toggle: {
                                    store.toggleSelection(for: item)
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

                            if expandedDuplicateIDs.contains(item.id), !item.duplicateCopies.isEmpty {
                                DuplicateCopiesView(item: item, store: store)
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
        guard !item.duplicateCopies.isEmpty else {
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

        return items.filter { item in
            matchesScope(item) && matchesSearch(item)
        }
    }

    private var hasActiveFilter: Bool {
        headerStyle == .large && (filterScope != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var emptyTitle: String {
        hasActiveFilter ? "No Matching Items" : "No Items Found"
    }

    private var emptyDescription: String {
        hasActiveFilter ? "Adjust search or filter scope to show more results." : "Run a scan or choose another category."
    }

    private func matchesScope(_ item: ReviewItem) -> Bool {
        switch filterScope {
        case .all:
            return true
        case .selected:
            return item.isSelected || item.duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
        case .highConfidence:
            return item.confidence == .high
        }
    }

    private func matchesSearch(_ item: ReviewItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        let searchableValues = [
            item.title,
            item.detail,
            item.location,
            item.reason
        ] + item.plannedURLs.map(\.path) + item.duplicateCopies.flatMap { [$0.url.lastPathComponent, $0.url.path] }

        return searchableValues.contains { value in
            value.localizedCaseInsensitiveContains(query)
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
    @Binding var searchText: String
    @Binding var filterScope: ReviewFilterScope

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterControls

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Search", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 320)
                }

                Picker("Filter", selection: $filterScope) {
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

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 320)

            Picker("Filter", selection: $filterScope) {
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

private struct ReviewRow: View {
    let item: ReviewItem
    let isSelected: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let toggleExpansion: () -> Void
    let reveal: () -> Void
    let open: () -> Void
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggleExpansion) {
                Image(systemName: item.duplicateCopies.isEmpty ? "circle" : isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(item.duplicateCopies.isEmpty ? .clear : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .disabled(item.duplicateCopies.isEmpty)

            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()

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
        }
        .padding(14)
        .contextMenu {
            Button("Preview", action: preview)
            Button("Reveal in Finder", action: reveal)
            Button("Open", action: open)
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

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(copy.url.lastPathComponent)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if copy.isRecommendedKeep {
                                Label("Keep", systemImage: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(.green)
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
                }
                .padding(.vertical, 8)
                .padding(.leading, 58)
                .padding(.trailing, 14)
            }
        }
        .background(.thinMaterial)
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
        case .high: .green
        case .medium: .orange
        case .low: .secondary
        }
    }
}
