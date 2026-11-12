import AppKit
import LittleTidyCore
import SwiftUI

/// Review of one everyday-space area: installers and archives, iPhone and iPad
/// backups, or Mail attachments. Nothing is preselected and everything moves
/// to the Trash. Items LittleTidy will not remove are shown, with the reason.
struct EverydayReviewSheet: View {
    let kind: EverydaySpaceKind
    @ObservedObject var store: ScanReviewStore
    let emptyTrash: () -> Void

    @State private var confirming = false

    private var card: SmartCareCardID { kind.cardID }
    private var items: [EverydaySpaceItem] { store.everydayItems(kind) }
    private var selected: [EverydaySpaceItem] { store.selectedEverydayItems(kind) }
    private var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let summary = store.cleanAllSummary {
                CleanupSummaryView(
                    summary: summary,
                    store: store,
                    emptyTrash: emptyTrash,
                    close: { store.dismissEverydayReview() },
                    showsDeveloperLink: false
                )
            } else if store.isCleaningDeveloperStorage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Moving to the Trash…")
                }
            } else {
                list
                footer
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            SmartCareTile(symbol: card.symbolName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(.title2.weight(.semibold))
                Text(card.explanation)
                    .font(.callout)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Label("Nothing to review here.", systemImage: "checkmark.circle")
                .foregroundStyle(Color.cleanerSecondaryText)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    private func row(_ item: EverydaySpaceItem) -> some View {
        SmartCarePanel {
            HStack(alignment: .top, spacing: 12) {
                if item.isSelectable {
                    Toggle("", isOn: Binding(
                        get: { store.everydaySelection.contains(item.id) },
                        set: { _ in store.toggleEverydaySelection(item) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Select \(item.name)")
                } else {
                    Image(systemName: "lock")
                        .foregroundStyle(Color.cleanerSecondaryText)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ByteCountFormatter.cleanerString(from: item.bytes))
                            .font(.callout)
                            .monospacedDigit()
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                    }
                    Text(item.reason).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                    if let warning = item.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.cleanerWarningText)
                    }
                    Text(item.consequence).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                    HStack(spacing: 10) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            .buttonStyle(.link)
                            .font(.subheadline)
                        if !item.isSelectable {
                            Text("LittleTidy does not remove this item.")
                                .font(.subheadline)
                                .foregroundStyle(Color.cleanerSecondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(selected.isEmpty
                 ? "Nothing selected."
                 : "\(selected.count == 1 ? "1 item" : "\(selected.count) items"), \(ByteCountFormatter.cleanerString(from: selectedBytes))")
                .font(.callout)
                .foregroundStyle(Color.cleanerSecondaryText)
            Spacer()
            Button("Close") { store.dismissEverydayReview() }.keyboardShortcut(.cancelAction)
            Button("Move to Trash…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .confirmationDialog(
                    "Move \(selected.count == 1 ? "1 item" : "\(selected.count) items") to the Trash?",
                    isPresented: $confirming,
                    titleVisibility: .visible
                ) {
                    Button("Move to Trash") { store.moveEverydaySelectionToTrash(kind) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(confirmationMessage)
                }
        }
    }

    private var confirmationMessage: String {
        let size = ByteCountFormatter.cleanerString(from: selectedBytes)
        switch kind {
        case .iosBackups:
            return "\(size) of device backups. They stay in the Trash until you empty it. If a device is lost or broken and no other backup exists, emptying the Trash makes them unrecoverable."
        case .mailDownloads:
            return "\(size) of attachment copies. Mail must be closed. They stay in the Trash until you empty it."
        case .installers:
            return "\(size) of installers and archives. They stay in the Trash until you empty it."
        case .appLeftovers:
            return "\(size) of settings and caches of apps that are no longer installed. They stay in the Trash until you empty it. If you reinstall one of the apps it starts fresh."
        }
    }
}
