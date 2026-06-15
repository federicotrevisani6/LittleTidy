import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScanReviewStore()
    @State private var showingSuggestedSelectionConfirmation = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            DetailView(store: store)
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.startOrCancelScan()
                        } label: {
                            Label(store.isScanning ? "Cancel Scan" : "Start Scan", systemImage: store.isScanning ? "xmark.circle" : "play.circle")
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                    }

                    ToolbarSpacer(.fixed)

                    ToolbarItem {
                        Menu {
                            Button {
                                store.chooseFolders()
                            } label: {
                                Label("Choose File Folders", systemImage: "folder.badge.plus")
                            }
                            .keyboardShortcut("o", modifiers: [.command])

                            Button {
                                store.chooseAppFolders()
                            } label: {
                                Label("Choose App Folders", systemImage: "app.badge")
                            }
                        } label: {
                            Label("Folders", systemImage: "folder")
                        }
                        .disabled(store.isScanning)
                    }

                    ToolbarSpacer(.fixed)

                    ToolbarItem {
                        Button {
                            showingSuggestedSelectionConfirmation = true
                        } label: {
                            Label("Select Suggested", systemImage: "checkmark.circle")
                        }
                        .disabled(store.isScanning || !store.suggestedSelectionPreview.hasItems)
                        .accessibilityHint("Opens a confirmation before selecting high-confidence non-cache items.")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .confirmationDialog(
            "Select suggested cleanup items?",
            isPresented: $showingSuggestedSelectionConfirmation,
            titleVisibility: .visible
        ) {
            let preview = store.suggestedSelectionPreview
            Button("Select \(preview.itemCount) Suggested Items") {
                store.applyBulkSelection(.suggestedWithoutCaches)
            }
            .disabled(!preview.hasItems)

            if store.reviewedCachesSelectionPreview.hasItems {
                Button("Review Caches First") {
                    store.selectedSection = .caches
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(suggestedSelectionMessage)
        }
    }

    private var suggestedSelectionMessage: String {
        let preview = store.suggestedSelectionPreview
        var lines = [
            "\(preview.itemCount) items, \(preview.filesystemEntryCount) filesystem entries, \(ByteCountFormatter.cleanerString(from: preview.bytes)) will be selected.",
            "Nothing moves to Trash until you review the Cleanup Plan and confirm the final action."
        ]

        if !preview.categoryBreakdown.isEmpty {
            lines.append("")
            lines.append(contentsOf: preview.categoryBreakdown.map { breakdown in
                "\(breakdown.category.displayTitle): \(breakdown.itemCount) items, \(ByteCountFormatter.cleanerString(from: breakdown.bytes))"
            })
        }

        if preview.excludesCaches {
            lines.append("")
            lines.append("Caches are excluded from suggested selection: \(preview.excludedCacheItemCount) cache items, \(ByteCountFormatter.cleanerString(from: preview.excludedCacheBytes)). Review caches separately.")
        }

        return lines.joined(separator: "\n")
    }
}
