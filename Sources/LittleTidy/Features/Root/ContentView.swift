import LittleTidyCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = ScanReviewStore()
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            DetailView(store: store)
                .searchable(text: $store.reviewSearchText, prompt: "Filter items…")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button {
                                store.chooseFolders()
                            } label: {
                                Label("Add Folders…", systemImage: "folder.badge.plus")
                            }
                            .keyboardShortcut("o", modifiers: [.command])

                            Button {
                                store.chooseAppFolders()
                            } label: {
                                Label("Add Application Folders…", systemImage: "app.badge")
                            }

                            Divider()

                            Button("Restore Default Locations") {
                                store.resetScanSettings()
                            }
                        } label: {
                            Label("Locations", systemImage: "folder")
                        }
                        .disabled(store.isScanning)

                        if !store.selectedItems.isEmpty && store.selectedSection != .cleanupPlan {
                            Button {
                                store.selectedSection = .cleanupPlan
                            } label: {
                                Label(
                                    "Review & Clean (\(ByteCountFormatter.cleanerString(from: store.selectedBytes)))",
                                    systemImage: "arrow.right.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            store.startOrCancelScan()
                        } label: {
                            Label(
                                store.isScanning ? "Cancel Scan" : "Scan",
                                systemImage: store.isScanning ? "xmark.circle" : "arrow.triangle.2.circlepath"
                            )
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.accentColor)
                            Text("Drop folder to scan or application to inspect leftovers")
                                .font(.headline)
                        }
                    )
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(item: $store.pendingUninstallEvent) { event in
            AppLeftoverPromptView(
                event: event,
                onConfirmClean: { selectedLeftovers in
                    store.executeLeftoverCleanup(for: event, selectedLeftovers: selectedLeftovers)
                },
                onDismiss: {
                    store.pendingUninstallEvent = nil
                }
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var droppedURLs: [URL] = []
            for provider in providers {
                if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }) {
                    droppedURLs.append(url)
                }
            }
            if !droppedURLs.isEmpty {
                store.handleDroppedURLs(droppedURLs)
            }
        }
        return true
    }
}
