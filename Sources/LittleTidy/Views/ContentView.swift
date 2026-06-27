import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScanReviewStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            DetailView(store: store)
                .safeAreaInset(edge: .bottom) {
                    CleanupCartBar(store: store)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.startOrCancelScan()
                        } label: {
                            Label(store.isScanning ? "Cancel Scan" : "Scan", systemImage: store.isScanning ? "xmark.circle" : "play.circle")
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
                }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Persistent cart shown at the bottom of the detail pane whenever items are
/// selected. It surfaces the running selection total and routes to the cleanup
/// plan, so the plan no longer needs to be a top-level sidebar destination.
private struct CleanupCartBar: View {
    @ObservedObject var store: ScanReviewStore

    private var isVisible: Bool {
        !store.selectedItems.isEmpty && store.selectedSection != .cleanupPlan
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(store.selectedItems.count) item\(store.selectedItems.count == 1 ? "" : "s") selected")
                        .font(.subheadline.weight(.semibold))
                    Text("\(ByteCountFormatter.cleanerString(from: store.selectedBytes)) · \(store.selectedFilesystemEntryCount) files & folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.clearSelection()
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    store.selectedSection = .cleanupPlan
                } label: {
                    Label("Review & Clean", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
