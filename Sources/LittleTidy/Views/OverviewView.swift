import LittleTidyCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingAdvancedSettings = false

    private var hasResults: Bool {
        !store.items.isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 18) {
                if !hasResults && !store.isScanning {
                    setupGuidePanel
                } else {
                    scanActionPanel
                }

                if store.isScanning {
                    ScanProgressCard(store: store)
                }

                if store.scanDidFail {
                    EmptyStateCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: .cleanerWarning,
                        title: "Scan didn’t finish",
                        message: store.statusMessage
                    ) {
                        Button("Try Again") {
                            store.startOrCancelScan()
                        }
                        Button("Choose Folders") {
                            store.chooseFolders()
                        }
                        Button("Full Disk Access") {
                            store.openFullDiskAccessSettings()
                        }
                    }
                } else if !hasResults && !store.isScanning {
                    if store.hasCompletedScan {
                        EmptyStateCard(
                            icon: "checkmark.seal.fill",
                            tint: .cleanerSuccess,
                            title: "Nothing to clean up",
                            message: "No duplicates, large files, or unused apps were found in the selected folders."
                        ) {
                            Button("Scan Another Folder") {
                                store.chooseFolders()
                            }
                            Button("Adjust Thresholds") {
                                showingAdvancedSettings = true
                            }
                        }
                    }
                }

                if hasResults {
                    resultsPanel
                }

                ScanIssuesView(store: store)

                if !store.isScanning {
                    advancedSettingsPanel
                }
            }
        }
    }

    private var scanActionPanel: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review Cleanup")
                    .font(.largeTitle.weight(.semibold))
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TotalBadge(title: "Selected", bytes: store.selectedBytes)

            Button {
                store.startOrCancelScan()
            } label: {
                Label(
                    store.isScanning ? "Cancel Scan" : (hasResults ? "Rescan" : "Start Scan"),
                    systemImage: store.isScanning ? "xmark.circle" : "play.circle.fill"
                )
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(18)
        .cleanerSurface()
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Results")
                    .font(.title2.weight(.semibold))
                Text("Review candidates by category before building the cleanup plan.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ReviewStepRow(index: 1, section: .duplicates, bytes: store.reclaimableBytes(for: .duplicate), selectedCount: store.selectedCount(for: .duplicate), store: store)
                ReviewStepRow(index: 2, section: .largeFiles, bytes: store.reclaimableBytes(for: .largeFile), selectedCount: store.selectedCount(for: .largeFile), store: store)
                ReviewStepRow(index: 3, section: .unusedApps, bytes: store.reclaimableBytes(for: .unusedApp), selectedCount: store.selectedCount(for: .unusedApp), store: store)
                ReviewStepRow(index: 4, section: .caches, bytes: store.reclaimableBytes(for: .cache), selectedCount: store.selectedCount(for: .cache), store: store)
            }
        }
        .padding(16)
        .cleanerSurface()
    }

    private var setupGuidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Up Scan")
                    .font(.title2.weight(.semibold))
                Text("Choose what LittleTidy can inspect, confirm access, then start the scan.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                SetupStep(number: 1, title: "Choose folders", detail: "\(store.scanRoots.count) file roots, \(store.appRoots.count) app roots") {
                    Menu {
                        Button {
                            store.chooseFolders()
                        } label: {
                            Label("Choose File Folders", systemImage: "folder.badge.plus")
                        }
                        Button {
                            store.chooseAppFolders()
                        } label: {
                            Label("Choose App Folders", systemImage: "app.badge")
                        }
                    } label: {
                        Label("Folders", systemImage: "folder")
                    }
                }

                SetupStep(number: 2, title: "Check access", detail: store.hasPermissionWarnings ? "Permission attention needed" : "Selected folders are ready") {
                    Label(store.hasPermissionWarnings ? "Review below" : "Ready", systemImage: store.hasPermissionWarnings ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.hasPermissionWarnings ? Color.cleanerWarning : Color.cleanerSuccess)
                }

                SetupStep(number: 3, title: "Start scan", detail: "Nothing is selected or moved automatically") {
                    Button {
                        store.startOrCancelScan()
                    } label: {
                        Label("Start Scan", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(store.scanRoots.isEmpty)
                }
            }

            if store.hasPermissionWarnings {
                PermissionReadinessView(store: store)
            }

            DisclosureGroup {
                ScanEvidenceView(store: store)
            } label: {
                Label("Selected Scan Scope", systemImage: "folder").font(.headline)
            }
        }
        .padding(18)
        .cleanerSurface()
    }

    private var advancedSettingsPanel: some View {
        DisclosureGroup(isExpanded: $showingAdvancedSettings) {
            ScanSettingsView(store: store) {
                showingAdvancedSettings = false
            }
        } label: {
            Label("Advanced Scan Settings", systemImage: "slider.horizontal.3").font(.headline)
        }
    }
}

private struct SetupStep<Actions: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                Text(title)
                    .font(.headline)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cleanerSubtleSurface()
    }
}

private struct ReviewStepRow: View {
    let index: Int
    let section: SidebarSection
    let bytes: Int64
    let selectedCount: Int
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Button {
            store.selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Image(systemName: section.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    Text(selectedCount > 0 ? "\(selectedCount) selected" : "Not selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.cleanerString(from: bytes))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cleanerInteractiveSurface(cornerRadius: 8)
        .accessibilityLabel("Review \(section.title), \(ByteCountFormatter.cleanerString(from: bytes)) reclaimable, \(selectedCount) selected")
    }
}

private struct EmptyStateCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                actions
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .cleanerSurface()
    }
}

private struct PermissionReadinessView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Access Readiness", systemImage: store.hasPermissionWarnings ? "lock.trianglebadge.exclamationmark" : "checkmark.shield")
                    .font(.headline)
                Spacer()
                Button {
                    store.refreshPermissionReadiness()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)

                Button {
                    store.openFullDiskAccessSettings()
                } label: {
                    Label("Full Disk Access", systemImage: "gearshape")
                }
            }

            ForEach(store.permissionReadinessItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName(for: item.severity))
                        .foregroundStyle(color(for: item.severity))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(16)
        .cleanerSurface()
    }

    private func iconName(for severity: PermissionReadinessItem.Severity) -> String {
        switch severity {
        case .ready:
            return "checkmark.circle.fill"
        case .advisory:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for severity: PermissionReadinessItem.Severity) -> Color {
        switch severity {
        case .ready:
            return .cleanerSuccess
        case .advisory:
            return .cleanerInfo
        case .warning:
            return .cleanerWarning
        }
    }
}

private struct ScanProgressCard: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.scanPhase, systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                if store.rootCount > 0 {
                    Text("\(store.currentRootIndex) of \(store.rootCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: store.progress == 0 ? nil : store.progress)

            if let currentScanLocation = store.currentScanLocation {
                Text(currentScanLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 18) {
                Metric(label: "Files", value: "\(store.scannedFiles)")
                Metric(label: "Scanned", value: ByteCountFormatter.cleanerString(from: store.scannedBytes))
                Metric(label: "Skipped", value: "\(store.skippedItems)")
                Metric(label: "Permission gaps", value: "\(store.permissionErrors)")
            }
        }
        .padding(16)
        .cleanerSurface()
    }
}

private struct TotalBadge: View {
    let title: String
    let bytes: Int64

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.cleanerString(from: bytes))
                .font(.title2.weight(.semibold))
        }
    }
}

private struct ScanEvidenceView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.scanRoots.isEmpty {
                Text("No folders selected.")
                    .foregroundStyle(.secondary)
            } else {
                Text("File roots")
                    .font(.caption.weight(.semibold))
                ForEach(store.scanRoots, id: \.standardizedFileURL) { root in
                    Text(root.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !store.appRoots.isEmpty {
                Text("App roots")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 4)
                ForEach(store.appRoots, id: \.standardizedFileURL) { root in
                    Text(root.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 18) {
                Metric(label: "Files", value: "\(store.scannedFiles)")
                Metric(label: "Scanned", value: ByteCountFormatter.cleanerString(from: store.scannedBytes))
                Metric(label: "Skipped", value: "\(store.skippedItems)")
                Metric(label: "Permission gaps", value: "\(store.permissionErrors)")
            }
        }
        .padding(16)
        .cleanerSurface()
    }
}

private struct ScanIssuesView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        if !store.scanIssues.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.scanIssues.prefix(12)) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: issue.kind == .permissionDenied ? "lock.trianglebadge.exclamationmark" : "minus.circle")
                                .foregroundStyle(issue.kind == .permissionDenied ? Color.cleanerWarning : Color.secondary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.url.path(percentEncoded: false))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(issue.kind.rawValue): \(issue.message)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    if store.scanIssues.count > 12 {
                        Text("\(store.scanIssues.count - 12) more scan issues not shown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Scan Issues", systemImage: "exclamationmark.triangle")
                    .font(.headline)
            }
            .padding(16)
            .cleanerSurface()
        }
    }
}

private struct ScanSettingsView: View {
    @ObservedObject var store: ScanReviewStore
    let collapseAdvancedSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Duplicate minimum")
                        .foregroundStyle(.secondary)
                    Stepper(ByteCountFormatter.cleanerString(from: store.minimumDuplicateSize), value: $store.minimumDuplicateSize, in: 0...100_000_000, step: 500_000)
                }

                GridRow {
                    Text("Large file threshold")
                        .foregroundStyle(.secondary)
                    Stepper(ByteCountFormatter.cleanerString(from: store.largeFileThreshold), value: $store.largeFileThreshold, in: 1_000_000...20_000_000_000, step: 100_000_000)
                }

                GridRow {
                    Text("Hidden files")
                        .foregroundStyle(.secondary)
                    Toggle("Include", isOn: $store.includeHiddenFiles)
                        .toggleStyle(.checkbox)
                }

                GridRow {
                    Text("System folders")
                        .foregroundStyle(.secondary)
                    Toggle("Allow", isOn: $store.includeSystemFolders)
                        .toggleStyle(.checkbox)
                }

                GridRow {
                    Text("App & dev caches")
                        .foregroundStyle(.secondary)
                    Toggle("Scan", isOn: $store.includeCaches)
                        .toggleStyle(.checkbox)
                }

                GridRow {
                    Text("Deep uninstall")
                        .foregroundStyle(.secondary)
                    Toggle("Include related app data", isOn: $store.includeRelatedAppData)
                        .toggleStyle(.checkbox)
                }
            }

            HStack {
#if DEBUG
                Button("Use QA Fixture") {
                    store.useFixtureSettings()
                    collapseAdvancedSettings()
                }
#endif
                Button("Reset Defaults") {
                    store.resetScanSettings()
                }
            }
        }
        .padding(16)
        .cleanerSurface()
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}
