import LittleTidyCore
import SwiftUI

// MARK: - Empty the Trash

/// The Trash's own confirmation. Emptying is permanent, so this sheet is
/// separate from every other cleanup flow and Cancel is its default.
struct TrashEmptySheet: View {
    @ObservedObject var store: ScanReviewStore
    @Binding var isPresented: Bool

    private var preview: TrashEmptyPreview? { store.trashPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.cleanerDanger, in: Circle())
                    .accessibilityHidden(true)
                Text("Empty the Trash?").font(.title2.weight(.semibold))
            }

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
                    Button("Cancel") { close() }.keyboardShortcut(.defaultAction)
                    Button(role: .destructive) { store.emptyTrash() } label: {
                        Label("Empty Trash", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cleanerDanger)
                    .disabled(store.isEmptyingTrash || (preview?.items.isEmpty ?? true))
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func close() {
        store.trashEmptyResult = nil
        isPresented = false
    }

    private func confirmView(_ preview: TrashEmptyPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(preview.items.count) items, \(ByteCountFormatter.cleanerString(from: preview.totalBytes)). This cannot be undone.")
                .fontWeight(.semibold)
            if preview.fromLastCleanupCount > 0 {
                SmartCarePanel(edge: Color.cleanerDanger, tint: Color.cleanerDanger) {
                    Label("Includes \(preview.fromLastCleanupCount) items LittleTidy moved here in its last cleanup. Emptying removes your only way to restore them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.cleanerDangerText)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.items.prefix(12)) { item in
                        HStack {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            if item.isFromLastCleanup {
                                Text("last cleanup")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.cleanerDangerText)
                            }
                            Spacer()
                            Text(ByteCountFormatter.cleanerString(from: item.bytes))
                                .foregroundStyle(Color.cleanerSecondaryText)
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if preview.items.count > 12 {
                        Text("and \(preview.items.count - 12) more")
                            .font(.subheadline)
                            .foregroundStyle(Color.cleanerSecondaryText)
                    }
                }
            }
            .frame(maxHeight: 180)
            Text("Items in use, locked or owned by another account are skipped.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
        }
    }

    private func resultView(_ result: TrashEmptyResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let blocked = result.blockedReason {
                Label(blocked, systemImage: "hand.raised").foregroundStyle(Color.cleanerWarningText)
            } else {
                Label("\(result.removed.count) items removed, \(ByteCountFormatter.cleanerString(from: result.bytesRemoved)) freed.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.cleanerSuccessText)
                if !result.skipped.isEmpty {
                    Text("\(result.skipped.count) skipped: \(result.skipped.prefix(3).map { $0.url.lastPathComponent }.joined(separator: ", ")).")
                        .font(.callout)
                        .foregroundStyle(Color.cleanerSecondaryText)
                }
                if !result.failed.isEmpty {
                    Text("\(result.failed.count) could not be removed.")
                        .font(.callout)
                        .foregroundStyle(Color.cleanerDangerText)
                }
            }
        }
    }
}

// MARK: - Clean all safe

/// One confirmation for everything LittleTidy classes as safe: what is
/// removed for good, what moves to the Trash, and what is left out and why.
struct CleanAllSafeSheet: View {
    @ObservedObject var store: ScanReviewStore
    @Binding var isPresented: Bool
    let emptyTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = store.cleanAllSummary {
                CleanupSummaryView(summary: summary, store: store, emptyTrash: emptyTrash, close: { close() })
            } else if store.isCleaningDeveloperStorage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cleaning…")
                }
            } else if let plan = store.cleanAllPlan {
                confirmView(plan)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func close() { isPresented = false }

    // MARK: Confirm

    private func confirmView(_ plan: SmartCareCleanPlan) -> some View {
        let permanent = plan.irreversibleItems
        let permanentBytes = permanent.reduce(Int64(0)) { $0 + $1.bytes }
        let reversible = plan.items.filter { !$0.isIrreversibleCleanup }
        let total = ByteCountFormatter.cleanerString(from: plan.totalBytes)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Clean \(total) safely?").font(.title2.weight(.semibold))
            Text("\(plan.itemCount == 1 ? "1 item" : "\(plan.itemCount) items") LittleTidy considers safe to rebuild. Nothing else is touched, and the Trash is not emptied.")
                .font(.callout)
                .foregroundStyle(Color.cleanerSecondaryText)

            if !permanent.isEmpty {
                SmartCarePanel(edge: Color.cleanerDanger, tint: Color.cleanerDanger) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Removed for good", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.cleanerDangerText)
                        Text("These cannot be restored.").font(.callout)
                        ForEach(permanentRows(permanent), id: \.text) { row in
                            HStack {
                                Text(row.text).font(.callout)
                                Spacer()
                                Text(row.count == 1 ? "1 item" : "\(row.count) items")
                                    .foregroundStyle(Color.cleanerSecondaryText)
                                Text(ByteCountFormatter.cleanerString(from: row.bytes)).monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
            }

            if !reversible.isEmpty {
                SmartCarePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Moved to the Trash", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.cleanerSuccessText)
                        Text("These can be restored until you empty the Trash.").font(.callout)
                        ForEach(plan.groups) { group in
                            let members = reversible.filter { SmartCareCleanPlanner.cardID(for: $0) == group.cardID }
                            if !members.isEmpty {
                                HStack {
                                    Text(group.cardID.title)
                                    Spacer()
                                    Text(members.count == 1 ? "1 item" : "\(members.count) items")
                                        .foregroundStyle(Color.cleanerSecondaryText)
                                    Text(ByteCountFormatter.cleanerString(from: members.reduce(Int64(0)) { $0 + $1.bytes }))
                                        .monospacedDigit()
                                        .frame(minWidth: 64, alignment: .trailing)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
            }

            if !plan.skipped.isEmpty {
                SmartCarePanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Left out for now", systemImage: "hand.raised")
                            .font(.headline)
                            .foregroundStyle(Color.cleanerWarningText)
                        Text("Not part of the total above.").font(.callout)
                        ForEach(plan.skipped.prefix(4)) { item in
                            Text("\(item.name): \(item.reason)")
                                .font(.subheadline)
                                .foregroundStyle(Color.cleanerSecondaryText)
                        }
                        if plan.skipped.count > 4 {
                            Text("and \(plan.skipped.count - 4) more")
                                .font(.subheadline)
                                .foregroundStyle(Color.cleanerSecondaryText)
                        }
                    }
                }
            }

            Text("Safety checks run again for each item. Anything in use is skipped, never forced.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)

            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button {
                    store.confirmCleanAllSafe()
                } label: {
                    HStack(spacing: 6) {
                        if !permanent.isEmpty { Image(systemName: "exclamationmark.triangle.fill") }
                        Text(permanent.isEmpty
                             ? "Clean \(total)"
                             : "Clean \(total) (\(ByteCountFormatter.cleanerString(from: permanentBytes)) permanent)")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(plan.isEmpty)
            }
        }
    }

    private struct PermanentRow { let text: String; let count: Int; let bytes: Int64 }

    private func permanentRows(_ items: [DeveloperStorageItem]) -> [PermanentRow] {
        func text(_ item: DeveloperStorageItem) -> String {
            switch item.cleanupMechanism {
            case .simctl, .xcodeManaged: "Simulators, removed with Apple's simctl"
            case .homebrewCleanup: "Homebrew downloads and old versions, removed with brew"
            default: "Items that are downloaded again when needed"
            }
        }
        return Dictionary(grouping: items, by: text)
            .map { PermanentRow(text: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
            .sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Result

/// The summary after a cleanup: what is free now, what waits in the Trash,
/// what a snapshot still holds, what was not removed and why, and how to undo.
struct CleanupSummaryView: View {
    let summary: CleanupSummary
    @ObservedObject var store: ScanReviewStore
    let emptyTrash: () -> Void
    let close: () -> Void

    private var title: String {
        if summary.removedCount == 0 { return "Nothing was cleaned" }
        return summary.hasProblems ? "Cleanup finished with problems" : "Cleanup finished"
    }

    private var titleSymbol: (String, Color) {
        if summary.removedCount == 0 { return ("exclamationmark.triangle.fill", Color.cleanerDanger) }
        return summary.hasProblems ? ("exclamationmark.triangle.fill", Color.cleanerWarning) : ("checkmark.circle.fill", Color.cleanerSuccess)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: titleSymbol.0).foregroundStyle(titleSymbol.1).font(.title2).accessibilityHidden(true)
                Text(title).font(.title2.weight(.semibold))
            }
            if summary.hasProblems, summary.removedCount > 0 {
                Text("\(summary.removedCount) done. \(summary.failed.count) failed, \(summary.skipped.count) skipped.")
                    .font(.callout)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }

            if summary.removedCount > 0 {
                panels
                if !summary.lines.isEmpty { cardLines }
            }
            if !summary.skipped.isEmpty {
                problemPanel("Skipped", summary.skipped, symbol: "hand.raised", tint: Color.cleanerWarningText,
                             footnote: "Nothing was changed for these.")
            }
            if !summary.failed.isEmpty {
                problemPanel("Failed", summary.failed, symbol: "exclamationmark.triangle.fill", tint: Color.cleanerDangerText, footnote: nil)
            }
            restoreSection
            actions
        }
    }

    // MARK: Number panels

    private var panels: some View {
        HStack(alignment: .top, spacing: 12) {
            numberPanel(symbol: "checkmark.circle.fill", tint: Color.cleanerSuccess, textTint: Color.cleanerSuccessText,
                        title: "Freed now", bytes: summary.freedNowBytes,
                        text: "Removed for good and available on your disk now.")
            if summary.inTrashBytes > 0 {
                numberPanel(symbol: "trash", tint: Color(nsColor: .systemGray), textTint: Color.cleanerSecondaryText,
                            title: "In the Trash", bytes: summary.inTrashBytes,
                            text: "Moved, not freed yet. The space comes back when you empty the Trash.") {
                    inTrashActions
                }
            }
            if let held = summary.heldBySnapshotBytes {
                numberPanel(symbol: "clock.arrow.circlepath", tint: Color.cleanerWarning, textTint: Color.cleanerWarningText,
                            title: "Held by a snapshot", bytes: held,
                            text: "Time Machine still keeps a copy of these removed files. macOS releases it when it needs the space.")
            }
        }
    }

    private func numberPanel(
        symbol: String, tint: Color, textTint: Color, title: String, bytes: Int64, text: String,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) -> some View {
        SmartCarePanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SmartCareTile(symbol: symbol, tint: textTint, fill: tint.opacity(0.18), size: 28)
                    Text(title).font(.callout.weight(.medium))
                }
                SmartCareNumber(bytes: bytes, size: 26)
                Text(text).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                actions()
            }
        }
    }

    @ViewBuilder
    private var inTrashActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !summary.restorable.isEmpty, store.restoreResult == nil {
                Button {
                    store.restoreLastCleanup()
                } label: {
                    Label(summary.restorable.count == 1 ? "Restore" : "Restore All", systemImage: "arrow.uturn.backward")
                }
                .disabled(store.isRestoring)
            }
            Button("Open Trash") { store.openTrash() }
            Divider()
            Button(role: .destructive, action: emptyTrash) {
                Label("Empty Trash…", systemImage: "trash").foregroundStyle(Color.cleanerDangerText)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: Lists

    private var cardLines: some View {
        SmartCarePanel {
            VStack(spacing: 0) {
                ForEach(summary.lines) { line in
                    HStack {
                        Text(line.cardID.title)
                        Spacer()
                        Text(line.removedCount == 1 ? "1 item" : "\(line.removedCount) items")
                            .foregroundStyle(Color.cleanerSecondaryText)
                        Text(ByteCountFormatter.cleanerString(from: line.bytes))
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                    if line.id != summary.lines.last?.id { Divider() }
                }
            }
        }
    }

    private func problemPanel(_ title: String, _ items: [CleanupSummary.Problem], symbol: String, tint: Color, footnote: String?) -> some View {
        SmartCarePanel {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(items.count) \(title.lowercased())", systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                ForEach(items.prefix(4)) { item in
                    Text("\(item.name): \(item.reason)")
                        .font(.subheadline)
                        .foregroundStyle(Color.cleanerSecondaryText)
                        .lineLimit(2)
                }
                if items.count > 4 {
                    Text("and \(items.count - 4) more").font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                }
                if let footnote {
                    Text(footnote).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        if let restore = store.restoreResult {
            VStack(alignment: .leading, spacing: 3) {
                Label(restore.restored.count == 1 ? "1 item put back." : "\(restore.restored.count) items put back.",
                      systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(Color.cleanerSuccessText)
                ForEach(Array(restore.notRestored.prefix(4)), id: \.name) { issue in
                    Text("\(issue.name): \(issue.reason)")
                        .font(.subheadline)
                        .foregroundStyle(Color.cleanerSecondaryText)
                }
            }
        } else if summary.irreversibleCount > 0 {
            Text(summary.irreversibleCount == 1
                 ? "1 removed item cannot be restored. It was removed through its own tool, not moved to the Trash."
                 : "\(summary.irreversibleCount) removed items cannot be restored. They were removed through their own tools, not moved to the Trash.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Open Developer Storage") {
                close()
                store.selectedSection = .developerStorage
            }
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
    }
}
