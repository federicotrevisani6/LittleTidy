import AppKit
import LittleTidyCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ScanRulesSettingsTab()
                .tabItem {
                    Label("Scan Rules", systemImage: "slider.horizontal.3")
                }

            DeletionSafetySettingsTab()
                .tabItem {
                    Label("Deletion & Safety", systemImage: "trash.slash.fill")
                }
        }
        .frame(width: 580, height: 490)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @State private var enableTrashWatcher: Bool
    @State private var notificationStatus: String = "Checking…"
    @State private var isFullDiskAccessGranted: Bool = FullDiskAccess.isGranted
    private let preferencesStore: ScanPreferencesStore

    init(preferencesStore: ScanPreferencesStore = .shared) {
        self.preferencesStore = preferencesStore
        let loaded = preferencesStore.load()
        _enableTrashWatcher = State(initialValue: loaded.enableTrashWatcher)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: isFullDiskAccessGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(isFullDiskAccessGranted ? Color.cleanerSuccess : Color.cleanerWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isFullDiskAccessGranted ? "Full Disk Access: Granted" : "Full Disk Access: Not Granted")
                                .font(.subheadline.weight(.medium))
                            Text(isFullDiskAccessGranted
                                 ? "LittleTidy has access to inspect system caches, application containers, and developer toolchains."
                                 : "Grant Full Disk Access to allow LittleTidy to scan all user caches, ~/Library containers, and application leftovers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(isFullDiskAccessGranted ? "System Settings…" : "Open Settings…") {
                            FullDiskAccess.openPrivacySettings()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Full Disk Access (FDA)", systemImage: "lock.shield")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Watch Trash for uninstalled applications", isOn: $enableTrashWatcher)
                        .onChange(of: enableTrashWatcher) { _, newValue in
                            var prefs = preferencesStore.load()
                            prefs.enableTrashWatcher = newValue
                            preferencesStore.save(prefs)
                            if newValue {
                                AppUninstallNotificationManager.shared.requestAuthorizationIfNeeded()
                            }
                        }

                    Text("When an application is moved to the Trash, LittleTidy automatically detects associated leftovers in ~/Library (Application Support, Caches, Preferences, Containers) and prompts you to clean them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: notificationIcon)
                                .foregroundStyle(notificationColor)
                            Text(notificationLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()

                            if authorizationStatus == .authorized {
                                Button("Send Test Notification") {
                                    sendTestNotification()
                                }
                                .controlSize(.small)
                            } else if authorizationStatus == .denied {
                                Button("System Settings…") {
                                    AppUninstallNotificationManager.shared.openNotificationSettings()
                                }
                                .controlSize(.small)
                            } else {
                                Button("Allow Notifications") {
                                    AppUninstallNotificationManager.shared.requestAuthorizationIfNeeded { _ in
                                        Task { @MainActor in
                                            checkNotificationStatus()
                                        }
                                    }
                                }
                                .controlSize(.small)
                            }
                        }

                        if let testNotificationFeedback {
                            Text(testNotificationFeedback)
                                .font(.caption2)
                                .foregroundStyle(Color.cleanerSuccess)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Label("App Uninstaller & Leftovers", systemImage: "trash")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LittleTidy automatically monitors developer toolchains and AI agent caches:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("• Xcode DerivedData, DeviceSupport, Simulators & SPM caches\n• CocoaPods, Carthage, Android AVD emulators\n• Cargo, uv, pnpm, Bun, Maven, Conda, Go caches\n• Ollama, Hugging Face, PyTorch, MLX, Claude Code & Cursor caches")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Developer & AI Toolchains", systemImage: "hammer")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updaterManager.automaticallyChecksForUpdates },
                        set: { updaterManager.automaticallyChecksForUpdates = $0 }
                    ))

                    HStack {
                        Text("Keep LittleTidy up to date with the latest cleanup rules and system compatibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Check for Updates…") {
                            updaterManager.checkForUpdates()
                        }
                        .controlSize(.small)
                        .disabled(!updaterManager.canCheckForUpdates)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkNotificationStatus()
            isFullDiskAccessGranted = FullDiskAccess.isGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isFullDiskAccessGranted = FullDiskAccess.isGranted
            checkNotificationStatus()
        }
    }

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var testNotificationFeedback: String? = nil

    private var notificationIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell"
        @unknown default: return "bell"
        }
    }

    private var notificationColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional: return Color.cleanerSuccess
        case .denied: return Color.cleanerDanger
        case .notDetermined: return Color.cleanerWarning
        @unknown default: return .secondary
        }
    }

    private var notificationLabel: String {
        switch authorizationStatus {
        case .authorized: return "Notifications: Active"
        case .denied: return "Notifications: Disabled in macOS Settings"
        case .notDetermined: return "Notifications: Not Authorized"
        case .provisional: return "Notifications: Provisional"
        @unknown default: return "Notifications: Checking…"
        }
    }

    private func sendTestNotification() {
        AppUninstallNotificationManager.shared.postTestNotification { result in
            Task { @MainActor in
                switch result {
                case .success:
                    testNotificationFeedback = "Test notification sent! Check the top right of your screen."
                case .failure(let error):
                    testNotificationFeedback = "Failed to send: \(error.localizedDescription)"
                }
            }
        }
    }

    private func checkNotificationStatus() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
            switch settings.authorizationStatus {
            case .authorized:
                notificationStatus = "Authorized"
            case .denied:
                notificationStatus = "Disabled in System Settings"
            case .notDetermined:
                notificationStatus = "Not Requested"
            case .provisional:
                notificationStatus = "Provisional"
            @unknown default:
                notificationStatus = "Unknown"
            }
        }
    }
}

// MARK: - Scan Rules Tab

private struct ScanRulesSettingsTab: View {
    @State private var includeHiddenFiles: Bool
    @State private var includeSystemFolders: Bool
    @State private var minimumDuplicateSize: Int64
    @State private var largeFileThreshold: Int64
    private let preferencesStore: ScanPreferencesStore

    init(preferencesStore: ScanPreferencesStore = .shared) {
        self.preferencesStore = preferencesStore
        let loaded = preferencesStore.load()
        _includeHiddenFiles = State(initialValue: loaded.includeHiddenFiles)
        _includeSystemFolders = State(initialValue: loaded.includeSystemFolders)
        _minimumDuplicateSize = State(initialValue: loaded.minimumDuplicateSize)
        _largeFileThreshold = State(initialValue: loaded.largeFileThreshold)
    }

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Duplicate minimum size")
                            .font(.subheadline)
                        Stepper(ByteCountFormatter.cleanerString(from: minimumDuplicateSize), value: $minimumDuplicateSize, in: 0...100_000_000, step: 500_000)
                            .controlSize(.small)
                            .onChange(of: minimumDuplicateSize) { _, _ in savePreferences() }
                    }

                    GridRow {
                        Text("Large file threshold")
                            .font(.subheadline)
                        Stepper(ByteCountFormatter.cleanerString(from: largeFileThreshold), value: $largeFileThreshold, in: 1_000_000...20_000_000_000, step: 100_000_000)
                            .controlSize(.small)
                            .onChange(of: largeFileThreshold) { _, _ in savePreferences() }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Size Thresholds", systemImage: "ruler")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Include dotfiles and hidden items in analysis", isOn: $includeHiddenFiles)
                        .controlSize(.small)
                        .onChange(of: includeHiddenFiles) { _, _ in savePreferences() }

                    Toggle("Scan system-level temporary and Library caches", isOn: $includeSystemFolders)
                        .controlSize(.small)
                        .onChange(of: includeSystemFolders) { _, _ in savePreferences() }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Scan Scope", systemImage: "magnifyingglass")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset Scan Rules to Defaults") {
                        minimumDuplicateSize = ScanPreferences.default.minimumDuplicateSize
                        largeFileThreshold = ScanPreferences.default.largeFileThreshold
                        includeHiddenFiles = ScanPreferences.default.includeHiddenFiles
                        includeSystemFolders = ScanPreferences.default.includeSystemFolders
                        savePreferences()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func savePreferences() {
        var prefs = preferencesStore.load()
        prefs.includeHiddenFiles = includeHiddenFiles
        prefs.includeSystemFolders = includeSystemFolders
        prefs.minimumDuplicateSize = minimumDuplicateSize
        prefs.largeFileThreshold = largeFileThreshold
        preferencesStore.save(prefs)
    }
}

// MARK: - Deletion & Safety Tab

private struct DeletionSafetySettingsTab: View {
    @State private var deletionMode: DeletionMode
    @State private var allowPermanentDeletion: Bool
    @State private var showingForceDeletePicker = false
    @State private var droppedURLsToForceDelete: [URL] = []
    @State private var showingForceDeleteConfirmation = false
    @State private var forceDeleteResultMessage: String?
    @State private var isForceDeleteTargeted = false

    private let preferencesStore: ScanPreferencesStore

    init(preferencesStore: ScanPreferencesStore = .shared) {
        self.preferencesStore = preferencesStore
        let loaded = preferencesStore.load()
        _deletionMode = State(initialValue: loaded.deletionMode)
        _allowPermanentDeletion = State(initialValue: loaded.allowPermanentDeletion)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Default Deletion Mode", selection: $deletionMode) {
                        Text("Move to Trash (Safe, Reversible)").tag(DeletionMode.moveToTrash)
                        Text("Permanently Delete (Skip Trash)").tag(DeletionMode.permanentDelete)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: deletionMode) { _, newMode in
                        if newMode == .permanentDelete {
                            allowPermanentDeletion = true
                        }
                        savePreferences()
                    }

                    if deletionMode == .permanentDelete {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.cleanerDanger)
                            Text("Warning: Skipping Trash permanently erases files immediately. This cannot be undone.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.cleanerDanger)
                        }
                        .padding(10)
                        .background(Color.cleanerDanger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text("Files will be moved to the macOS Trash via FileManager.trashItem and can be recovered if needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Deletion Method", systemImage: "trash.slash.fill")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drop stubborn files or directories here to immediately force delete them without placing them in the Trash:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(isForceDeleteTargeted ? Color.cleanerDanger : Color.secondary.opacity(0.4))
                            .background(isForceDeleteTargeted ? Color.cleanerDanger.opacity(0.08) : Color.primary.opacity(0.02))

                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.title3)
                                .foregroundStyle(Color.cleanerDanger)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Force Delete Files / Folders")
                                    .font(.subheadline.weight(.semibold))
                                Text("Drop files here or click to choose")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Choose Files…") {
                                chooseFilesToForceDelete()
                            }
                            .controlSize(.small)
                        }
                        .padding(12)
                    }
                    .frame(height: 64)
                    .onDrop(of: [.fileURL], isTargeted: $isForceDeleteTargeted) { providers in
                        handleDropForForceDelete(providers: providers)
                    }

                    if let message = forceDeleteResultMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.cleanerSuccess)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Instant Force Delete Tool", systemImage: "flame")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Xcode Build Protection", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("LittleTidy automatically detects when Xcode is running and pauses developer storage cleanup to prevent corrupting active build artifacts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Safety Policy", systemImage: "shield.lefthalf.filled")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Permanently delete \(droppedURLsToForceDelete.count) item\(droppedURLsToForceDelete.count == 1 ? "" : "s")?",
            isPresented: $showingForceDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Permanently Delete", role: .destructive) {
                executeImmediateForceDelete(urls: droppedURLsToForceDelete)
            }
            Button("Cancel", role: .cancel) {
                droppedURLsToForceDelete = []
            }
        } message: {
            Text("These items will be erased immediately from disk, skipping the Trash. This operation cannot be undone.")
        }
    }

    private func savePreferences() {
        var prefs = preferencesStore.load()
        prefs.deletionMode = deletionMode
        prefs.allowPermanentDeletion = allowPermanentDeletion
        preferencesStore.save(prefs)
    }

    private func chooseFilesToForceDelete() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Select to Force Delete"
        if panel.runModal() == .OK {
            droppedURLsToForceDelete = panel.urls
            if !droppedURLsToForceDelete.isEmpty {
                showingForceDeleteConfirmation = true
            }
        }
    }

    private func handleDropForForceDelete(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                self.droppedURLsToForceDelete = urls
                self.showingForceDeleteConfirmation = true
            }
        }
        return true
    }

    private func executeImmediateForceDelete(urls: [URL]) {
        Task { @MainActor in
            let executor = TrashExecutor()
            let result = await Task.detached(priority: .userInitiated) {
                executor.forceDelete(urls: urls)
            }.value

            forceDeleteResultMessage = "Permanently deleted \(result.trashed.count) item(s) (\(result.skipped.count) skipped)."
            droppedURLsToForceDelete = []
        }
    }
}
