import LittleTidyCore
import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScanReviewStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            ZStack(alignment: .bottom) {
                DetailView(store: store)

                FloatingSelectionIsland(store: store)
                    .padding(.bottom, 20)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.startOrCancelScan()
                    } label: {
                        Label(
                            store.isScanning ? "Annulla" : "Scansiona",
                            systemImage: store.isScanning ? "xmark.circle" : "sparkles"
                        )
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                }

                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            store.chooseFolders()
                        } label: {
                            Label("Cartelle File...", systemImage: "folder.badge.plus")
                        }
                        .keyboardShortcut("o", modifiers: [.command])

                        Button {
                            store.chooseAppFolders()
                        } label: {
                            Label("Cartelle Applicazioni...", systemImage: "app.badge")
                        }
                    } label: {
                        Label("Cartelle", systemImage: "folder")
                    }
                    .disabled(store.isScanning)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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
}

/// Modern floating capsule island shown at the bottom whenever files are selected.
private struct FloatingSelectionIsland: View {
    @ObservedObject var store: ScanReviewStore

    private var isVisible: Bool {
        !store.selectedItems.isEmpty && store.selectedSection != .cleanupPlan
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(store.selectedItems.count) element\(store.selectedItems.count == 1 ? "o" : "i") selezionat\(store.selectedItems.count == 1 ? "o" : "i")")
                            .font(.subheadline.weight(.bold))
                        Text("\(ByteCountFormatter.cleanerString(from: store.selectedBytes)) liberabili")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .frame(height: 22)

                Button {
                    store.clearSelection()
                } label: {
                    Text("Deseleziona")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    store.selectedSection = .cleanupPlan
                } label: {
                    Label("Rivedi e Pulisci", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        }
    }
}
