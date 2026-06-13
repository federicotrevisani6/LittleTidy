import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScanReviewStore()

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

                    ToolbarItem {
                        Button {
                            store.selectSuggested()
                        } label: {
                            Label("Select Suggested", systemImage: "checkmark.circle")
                        }
                        .disabled(store.isScanning || store.items.isEmpty)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
