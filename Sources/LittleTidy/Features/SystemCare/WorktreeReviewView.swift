import AppKit
import LittleTidyCore
import Observation
import SwiftUI

@MainActor
@Observable
final class WorktreeReviewStore {
    let root: URL
    var records: [GitWorktreeRecord] = []
    var issues: [String] = []
    var inspection: WorktreeInspection?
    var isWorking = false
    var isRemoving = false
    var message: String?
    @ObservationIgnored private let manager: GitWorktreeManager
    @ObservationIgnored private var operation: Task<Void, Never>?
    init(root: URL) { self.root = root; manager = GitWorktreeManager(root: root) }
    func scan() {
        guard !isWorking else { return }
        inspection = nil; isWorking = true; message = nil
        operation = Task {
            defer { isWorking = false; operation = nil }
            do {
                let result = try await manager.discover()
                try Task.checkCancellation()
                records = result.worktrees; issues = result.issues
            } catch is CancellationError { message = "Scan stopped. Results may be partial." }
            catch { message = error.localizedDescription }
        }
    }
    func check(_ record: GitWorktreeRecord) {
        guard !isWorking else { return }
        isWorking = true; message = nil
        operation = Task {
            defer { isWorking = false; operation = nil }
            do { inspection = try await manager.inspect(record) }
            catch is CancellationError { message = "Check stopped." }
            catch { inspection = nil; message = error.localizedDescription }
        }
    }
    func remove(ownerStopped: Bool) {
        guard !isWorking, let inspection else { return }
        let allowed = ScanPreferencesStore.shared.load().allowPermanentDeletion
        isWorking = true; isRemoving = true; message = nil
        operation = Task {
            defer { isWorking = false; isRemoving = false; operation = nil }
            do {
                try await manager.remove(inspection, allowPermanentDeletion: allowed, ownerStoppedConfirmed: ownerStopped)
                records.removeAll { $0.id == inspection.worktree.id }; self.inspection = nil
                message = "Worktree removed through Git. Its branch remains in the repository."
            } catch { self.inspection = nil; message = error.localizedDescription }
        }
    }
    func stop() { if !isRemoving { operation?.cancel() } }
}

struct WorktreeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: WorktreeReviewStore
    init(root: URL? = nil) {
        _model = State(initialValue: WorktreeReviewStore(root: root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/worktrees")))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Agent worktrees").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isRemoving)
            }
            Text(model.root.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Choose Folder…") { chooseFolder() }.disabled(model.isWorking)
                Button("Scan", systemImage: "arrow.clockwise") { model.scan() }.disabled(model.isWorking)
                if model.isWorking && !model.isRemoving { Button("Stop") { model.stop() } }
                Spacer()
                if model.isWorking { ProgressView(model.isRemoving ? "Removing…" : "Checking…").controlSize(.small) }
            }
            Text("Registered linked worktrees only. Nothing is selected automatically. Review each worktree and stop its owning agent before removal.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.callout).foregroundStyle(Color.cleanerWarning).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let inspection = model.inspection {
                        WorktreeInspectionView(inspection: inspection, model: model)
                    } else {
                        if model.records.isEmpty && !model.isWorking {
                            ContentUnavailableView("No linked worktrees found", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Choose a folder containing linked worktrees. Only worktrees inside the selected folder are listed; discovery is limited to four levels."))
                        }
                        ForEach(model.records) { record in WorktreeInventoryRow(record: record, model: model) }
                    }
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).foregroundStyle(Color.cleanerWarning).textSelection(.enabled) }
                }
            }
        }
        .padding(24).frame(width: 780, height: 560)
        .task { model.scan() }
        .onDisappear { model.stop() }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Inspect Worktrees"
        if panel.runModal() == .OK, let url = panel.url {
            model = WorktreeReviewStore(root: url); model.scan()
        }
    }
}

private struct WorktreeInventoryRow: View {
    let record: GitWorktreeRecord
    let model: WorktreeReviewStore
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(URL(fileURLWithPath: record.path).lastPathComponent).font(.headline)
                Text(record.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(record.branch ?? "Detached HEAD").font(.caption).foregroundStyle(.secondary)
                if record.locked { Text("Locked · removal blocked").font(.caption).foregroundStyle(Color.cleanerWarning) }
            }
            Spacer()
            Button("Review") { model.check(record) }.disabled(model.isWorking)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)]) }
        }.padding(14).cleanerSurface()
    }
}

private struct WorktreeInspectionView: View {
    let inspection: WorktreeInspection
    let model: WorktreeReviewStore
    @Environment(\.openSettings) private var openSettings
    @State private var ownerStopped = false
    @State private var allowPermanentRemoval = ScanPreferencesStore.shared.load().allowPermanentDeletion
    @State private var confirmingRemoval = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Worktree review").font(.headline)
                Spacer()
                Button("Back to List") { model.inspection = nil }.disabled(model.isWorking)
            }
            Text(inspection.worktree.path).font(.caption.monospaced()).textSelection(.enabled)
            Text(inspection.worktree.branch ?? "Detached HEAD").font(.callout.bold())
            Text("Size: \(inspection.bytes.map { ByteCountFormatter.cleanerString(from: $0) } ?? "Unknown")")
            Text(inspection.gitStatus).font(.callout)
            Text(inspection.activity).font(.callout)
            ForEach(Array(inspection.blockers.enumerated()), id: \.offset) { _, blocker in Text(blocker).foregroundStyle(Color.cleanerWarning) }
            if !inspection.changes.isEmpty {
                Text("Changes and ignored data (up to 100 entries)").font(.headline)
                Text(inspection.changes.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled)
            }
            if inspection.canRemove {
                Toggle("I have stopped the agent and other tools using this worktree", isOn: $ownerStopped)
                Text("Git removal permanently deletes this checkout and its local worktree metadata without Trash. The named branch and committed history remain. For app-managed worktrees, archive the associated task in its owning app first; Git removal does not archive task history.")
                    .font(.caption).foregroundStyle(Color.cleanerWarning)
                if !allowPermanentRemoval {
                    Text("Enable Allow Permanent Git Worktree Removal in Settings → Deletion & Safety before using Git removal.").font(.callout)
                    Button("Open Settings") { openSettings() }
                }
                Button("Remove Worktree…", role: .destructive) { confirmingRemoval = true }
                    .disabled(!ownerStopped || model.isWorking || !allowPermanentRemoval)
            }
        }.padding(14).cleanerSurface()
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            allowPermanentRemoval = ScanPreferencesStore.shared.load().allowPermanentDeletion
        }
        .confirmationDialog("Permanently remove this worktree?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove Worktree Permanently", role: .destructive) { model.remove(ownerStopped: ownerStopped) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(inspection.worktree.path)\nThe checkout will be removed through Git without Trash or force. Checks run again immediately before removal. The branch is kept.")
        }
    }
}
