import AppKit
import LittleTidyCore
import Observation
import SwiftUI

@MainActor
@Observable
final class StorageBrowserStore {
    let root: StorageLocation
    var path: String
    var requestID = UUID()
    var entries: [StorageFolderEntry] = []
    var isLoading = false
    var message: String?
    var hasLoaded = false
    var isStopped = false
    @ObservationIgnored private let explorer: FolderExplorer
    init(root: StorageLocation) {
        self.root = root; path = root.path
        explorer = FolderExplorer(allowedRoots: [URL(fileURLWithPath: root.path)])
    }
    func open(_ path: String) {
        self.path = path; isStopped = false; hasLoaded = false; entries = []; message = nil; requestID = UUID()
    }
    func stop() { isStopped = true; isLoading = false; requestID = UUID(); message = "Stopped. Sizes shown are partial." }
    func load() async {
        guard !isStopped else { return }
        let id = requestID, current = path
        isLoading = true; message = nil
        defer { if requestID == id { isLoading = false; hasLoaded = true } }
        do {
            let listing = try await explorer.list(at: URL(fileURLWithPath: current))
            try Task.checkCancellation()
            guard requestID == id else { return }
            entries = listing.entries
            if listing.isTruncated { message = "Showing the first 250 entries. Other entries have not been measured." }
            let deadline = Date().addingTimeInterval(60)
            for entry in listing.entries {
                try Task.checkCancellation()
                guard requestID == id else { return }
                if Date() > deadline {
                    message = "Measurement paused after one minute. Some sizes remain unknown; open a smaller folder to continue."
                    break
                }
                let measured: StorageFolderEntry
                do { measured = try await explorer.measure(entry) }
                catch is CancellationError { throw CancellationError() }
                catch { var failed = entry; failed.issue = error.localizedDescription; measured = failed }
                try Task.checkCancellation()
                guard requestID == id else { return }
                if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = measured }
            }
            entries.sort {
                if $0.bytes == $1.bytes { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return ($0.bytes ?? -1) > ($1.bytes ?? -1)
            }
        } catch is CancellationError { }
        catch { if requestID == id { message = error.localizedDescription } }
    }
}

struct StorageFolderBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: StorageBrowserStore
    @State private var showingWorktrees = false
    init(root: StorageLocation) { _model = State(initialValue: StorageBrowserStore(root: root)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore storage").font(.title2.bold())
                    Text(model.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Button("Back", systemImage: "arrow.up") { model.open(URL(fileURLWithPath: model.path).deletingLastPathComponent().path) }
                    .disabled(model.path == model.root.path)
                Button(model.isLoading ? "Stop" : "Refresh", systemImage: model.isLoading ? "stop.circle" : "arrow.clockwise") {
                    if model.isLoading { model.stop() } else { model.open(model.path) }
                }
                Button("Review Worktrees…") { showingWorktrees = true }
                Spacer()
                if model.isLoading { ProgressView("Measuring…").controlSize(.small) }
            }
            Text("Read-only exploration. Folder sizes can overlap and do not represent space safe to reclaim. Git changes and activity are not checked.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.callout).foregroundStyle(Color.cleanerWarning).textSelection(.enabled) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.hasLoaded && model.entries.isEmpty && model.message == nil {
                        ContentUnavailableView("No entries", systemImage: "folder", description: Text("This folder is empty."))
                    }
                    ForEach(model.entries) { entry in StorageFolderRow(entry: entry, model: model) }
                }
            }
        }
        .padding(24)
        .frame(width: 780, height: 560)
        .sheet(isPresented: $showingWorktrees) { WorktreeReviewView(root: URL(fileURLWithPath: model.path)) }
        .task(id: model.requestID) { await model.load() }
    }
}

private struct StorageFolderRow: View {
    let entry: StorageFolderEntry
    let model: StorageBrowserStore
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.headline).textSelection(.enabled)
                Text(entry.kind.title).font(.caption.bold()).foregroundStyle(Color.cleanerInfo)
                Text(entry.kind.explanation).font(.caption).foregroundStyle(.secondary)
                if let issue = entry.issue { Text(issue).font(.caption).foregroundStyle(Color.cleanerWarning).lineLimit(2).help(issue) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text(entry.bytes.map { ByteCountFormatter.cleanerString(from: $0) } ?? "Unknown")
                    .font(.callout.bold().monospacedDigit())
                if entry.canExplore { Button("Open") { model.open(entry.path) } }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
            }
        }
        .padding(14)
        .cleanerSurface()
    }
}
