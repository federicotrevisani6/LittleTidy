import LittleTidyCore
import SwiftUI

struct SmartCareView: View {
    @ObservedObject var store: ScanReviewStore
    let systemCare: SystemCareStore

    @State private var showTrashSheet = false

    private var cards: [SmartCareCard] {
        store.smartCareCards(startupItemCount: systemCare.startup.count)
    }

    private var hasResults: Bool {
        store.hasCompletedScan || store.isScanning || !store.developerStorageInventory.items.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if hasResults {
                    let cards = cards
                    ForEach(SmartCareGroup.allCases) { group in
                        groupSection(group, cards: cards.filter { $0.cardID.group == group })
                    }
                } else {
                    preScan
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showTrashSheet) {
            TrashEmptySheet(store: store, isPresented: $showTrashSheet)
        }
        .onAppear {
            if store.trashPreview == nil && !store.trashNeedsAccess { store.refreshTrashPreview() }
        }
    }

    // MARK: - Header

    private var header: some View {
        let cards = cards
        let headline = SmartCareBuilder.headline(for: cards)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Care")
                        .font(.title2.weight(.semibold))
                    if store.isScanning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(store.currentScanLocation.map { "Reading \($0)" } ?? store.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else if hasResults {
                        Text(headlineText(headline))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("One scan looks at caches, developer data, AI tools, the Trash, apps and snapshots.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    if store.isScanning {
                        store.startOrCancelScan()
                    } else {
                        store.startSmartCareScan()
                        if !systemCare.isScanning { systemCare.scan() }
                    }
                } label: {
                    Label(store.isScanning ? "Cancel" : (hasResults ? "Scan Again" : "Scan"),
                          systemImage: store.isScanning ? "xmark.circle" : "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if store.isScanning {
                ProgressView(value: store.progress)
            }
        }
    }

    private func headlineText(_ headline: SmartCareHeadline) -> String {
        let safe = ByteCountFormatter.cleanerString(from: headline.safeBytes)
        let review = ByteCountFormatter.cleanerString(from: headline.reviewBytes)
        return "\(safe) you can clean safely · \(review) to review first"
    }

    private var preScan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nothing is removed during a scan.", systemImage: "checkmark.shield")
            Label("Each card explains what it found and what removing it means.", systemImage: "text.bubble")
            Label("Clean only acts on items LittleTidy considers safe to rebuild.", systemImage: "arrow.triangle.2.circlepath")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerSubtleSurface()
    }

    // MARK: - Groups

    private func groupSection(_ group: SmartCareGroup, cards: [SmartCareCard]) -> some View {
        let active = cards.filter { !$0.isEmpty }
        let empty = cards.filter(\.isEmpty)
        return VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.headline)
            if !active.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(active) { card in
                        SmartCareCardView(
                            card: card,
                            store: store,
                            isEmptyingTrash: store.isEmptyingTrash,
                            emptyTrash: { showTrashSheet = true }
                        )
                    }
                }
            }
            if !empty.isEmpty {
                Text("Nothing to clean in: " + empty.map(\.cardID.title).joined(separator: ", ") + ".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmartCareCardView: View {
    let card: SmartCareCard
    @ObservedObject var store: ScanReviewStore
    let isEmptyingTrash: Bool
    let emptyTrash: () -> Void

    private var totalBytes: Int64 { card.recommendedBytes + card.reviewBytes + card.protectedBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.cardID.title)
                .font(.headline)

            content

            Text(card.cardID.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .cleanerInteractiveSurface()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch card.state {
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…").foregroundStyle(.secondary)
            }
        case .needsAccess(let message):
            Label(message, systemImage: "lock")
                .font(.callout)
                .foregroundStyle(Color.cleanerWarning)
        case .blocked(let message):
            Label(message, systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(Color.cleanerWarning)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Color.cleanerDanger)
        case .empty, .ready:
            if totalBytes > 0 || card.itemCount > 0 {
                Text(ByteCountFormatter.cleanerString(from: totalBytes))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text(tierSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let info = card.infoText {
                Text(info)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tierSummary: String {
        if card.cardID == .trash {
            return "\(card.itemCount) items"
        }
        var parts: [String] = []
        if card.recommendedBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.recommendedBytes)) safe") }
        if card.reviewBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.reviewBytes)) to review") }
        if card.protectedBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.protectedBytes)) protected") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            Spacer()
            if card.cardID == .trash {
                Button("Open Trash") { store.openTrash() }
                if case .ready = card.state {
                    Button("Empty Trash…", role: .destructive, action: emptyTrash)
                        .disabled(isEmptyingTrash)
                }
            } else {
                Button("Review") { store.reviewSmartCare(card) }
                if card.canClean {
                    Button("Clean…") { store.prepareSmartCareClean(card) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .controlSize(.small)
    }
}

/// The Trash card's own confirmation. Emptying is permanent, so this sheet
/// is separate from every other cleanup flow.
private struct TrashEmptySheet: View {
    @ObservedObject var store: ScanReviewStore
    @Binding var isPresented: Bool

    private var preview: TrashEmptyPreview? { store.trashPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Empty the Trash?")
                .font(.title3.weight(.semibold))

            if store.isEmptyingTrash {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Emptying the Trash…")
                }
            } else if let result = store.trashEmptyResult {
                resultView(result)
            } else if let preview {
                confirmView(preview)
            }

            HStack {
                Spacer()
                if store.trashEmptyResult != nil {
                    Button("Done") { close() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                    Button("Empty Trash", role: .destructive) { store.emptyTrash() }
                        .disabled(store.isEmptyingTrash || (preview?.items.isEmpty ?? true))
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func close() {
        store.trashEmptyResult = nil
        isPresented = false
    }

    private func confirmView(_ preview: TrashEmptyPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(preview.items.count) items, \(ByteCountFormatter.cleanerString(from: preview.totalBytes)). This cannot be undone.")
                .fontWeight(.medium)
            if preview.fromLastCleanupCount > 0 {
                Label("Includes \(preview.fromLastCleanupCount) items LittleTidy moved here in its last cleanup. Emptying removes your only way to restore them.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Color.cleanerWarning)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.items.prefix(12)) { item in
                        HStack {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            if item.isFromLastCleanup { Text("last cleanup").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            Text(ByteCountFormatter.cleanerString(from: item.bytes)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if preview.items.count > 12 {
                        Text("and \(preview.items.count - 12) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 180)
            Text("Items in use, locked or owned by another account are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultView(_ result: TrashEmptyResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let blocked = result.blockedReason {
                Label(blocked, systemImage: "hand.raised").foregroundStyle(Color.cleanerWarning)
            } else {
                Label("\(result.removed.count) items removed, \(ByteCountFormatter.cleanerString(from: result.bytesRemoved)) freed.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(Color.cleanerSuccess)
                if !result.skipped.isEmpty {
                    Text("\(result.skipped.count) skipped: \(result.skipped.prefix(3).map { $0.url.lastPathComponent }.joined(separator: ", ")).")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !result.failed.isEmpty {
                    Text("\(result.failed.count) could not be removed.")
                        .font(.callout).foregroundStyle(Color.cleanerDanger)
                }
            }
        }
    }
}
