import LittleTidyCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingAdvancedSettings = false

    private var hasResults: Bool {
        !store.items.isEmpty
    }

    private var totalReclaimableBytes: Int64 {
        [.duplicate, .largeFile, .unusedApp, .cache].reduce(Int64(0)) { (sum: Int64, category: CleanupCategory) in
            sum + store.reclaimableBytes(for: category)
        }
    }

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 18) {
                if store.isScanning {
                    ScanningHero(store: store)
                    ScanProgressCard(store: store)
                } else if store.scanDidFail {
                    ScanFailureCard(store: store)
                } else if hasResults {
                    ResultsHero(store: store, totalBytes: totalReclaimableBytes)
                    CategorySummaryGrid(store: store)
                } else if store.hasCompletedScan {
                    NothingToCleanCard(store: store) {
                        showingAdvancedSettings = true
                    }
                } else {
                    StartHero(store: store)
                }

                ScanIssuesView(store: store)

                if !store.isScanning {
                    setupAndSettingsPanel
                }
            }
        }
    }

    // MARK: - Setup & advanced settings (collapsed by default)

    private var setupAndSettingsPanel: some View {
        DisclosureGroup(isExpanded: $showingAdvancedSettings) {
            VStack(alignment: .leading, spacing: 16) {
                ScanScopePanel(store: store)
                if store.hasPermissionWarnings {
                    PermissionReadinessView(store: store)
                }
                ScanSettingsView(store: store)
            }
            .padding(.top, 8)
        } label: {
            Label("Scan Settings & Folders", systemImage: "slider.horizontal.3").font(.headline)
        }
    }
}

// MARK: - Heroes

private struct StartHero: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tidy up your Mac")
                    .font(.largeTitle.weight(.bold))
                Text("LittleTidy finds duplicates, large files, unused apps, and caches you can safely remove. Nothing is deleted — everything goes to the Trash so you can undo.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button {
                    store.startOrCancelScan()
                } label: {
                    Label("Scan My Mac", systemImage: "play.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.scanRoots.isEmpty)

                Text(store.scanRoots.isEmpty
                     ? "Choose folders below to get started."
                     : "Ready to scan \(store.scanRoots.count) location\(store.scanRoots.count == 1 ? "" : "s").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.hasPermissionWarnings {
                Label("Some folders need permission — see Scan Settings & Folders below.", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.cleanerWarning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .cleanerSurface()
    }
}

private struct ResultsHero: View {
    @ObservedObject var store: ScanReviewStore
    let totalBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up to \(ByteCountFormatter.cleanerString(from: totalBytes)) can be freed")
                        .font(.largeTitle.weight(.bold))
                    Text("Safe items are pre-selected. Review anything else, then move it all to the Trash.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.startOrCancelScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            HStack(spacing: 12) {
                Button {
                    store.selectSuggested()
                    store.selectedSection = .cleanupPlan
                } label: {
                    Label("Clean Safe Items", systemImage: "sparkles")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!store.suggestedSelectionPreview.hasItems)
                .help("Selects high-confidence safe items and opens the cleanup plan.")

                let preview = store.suggestedSelectionPreview
                if preview.hasItems {
                    Text("\(preview.itemCount) safe items · \(ByteCountFormatter.cleanerString(from: preview.bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TotalBadge(title: "Selected now", bytes: store.selectedBytes)
            }
        }
        .padding(22)
        .cleanerSurface()
    }
}

private struct ScanningHero: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scanning…")
                    .font(.largeTitle.weight(.semibold))
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.startOrCancelScan()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .controlSize(.large)
        }
        .padding(22)
        .cleanerSurface()
    }
}

// MARK: - Category cards

private struct CategorySummaryGrid: View {
    @ObservedObject var store: ScanReviewStore

    private let order: [(SidebarSection, CleanupCategory)] = [
        (.duplicates, .duplicate),
        (.largeFiles, .largeFile),
        (.unusedApps, .unusedApp),
        (.caches, .cache)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review by category")
                .font(.title2.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(order, id: \.0) { section, category in
                    CategoryCard(
                        section: section,
                        bytes: store.reclaimableBytes(for: category),
                        selectedCount: store.selectedCount(for: category),
                        totalCount: store.items(for: category).count,
                        store: store
                    )
                }
            }
        }
    }
}

private struct CategoryCard: View {
    let section: SidebarSection
    let bytes: Int64
    let selectedCount: Int
    let totalCount: Int
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Button {
            store.selectedSection = section
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(ByteCountFormatter.cleanerString(from: bytes))
                    .font(.title2.weight(.semibold))
                Text(section.title)
                    .font(.subheadline.weight(.medium))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cleanerInteractiveSurface(cornerRadius: 14)
        .accessibilityLabel("\(section.title), \(ByteCountFormatter.cleanerString(from: bytes)), \(selectedCount) of \(totalCount) selected")
    }

    private var detailText: String {
        if totalCount == 0 {
            return "Nothing found"
        }
        if selectedCount > 0 {
            return "\(selectedCount) of \(totalCount) selected"
        }
        return "\(totalCount) found"
    }
}

// MARK: - Empty / failure states

private struct NothingToCleanCard: View {
    @ObservedObject var store: ScanReviewStore
    let adjustThresholds: () -> Void

    var body: some View {
        EmptyStateCard(
            icon: "checkmark.seal.fill",
            tint: .cleanerSuccess,
            title: "Nothing to clean up",
            message: "No duplicates, large files, or unused apps were found in the selected folders."
        ) {
            Button("Scan Another Folder") { store.chooseFolders() }
            Button("Adjust Settings", action: adjustThresholds)
        }
    }
}

private struct ScanFailureCard: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        EmptyStateCard(
            icon: "exclamationmark.triangle.fill",
            tint: .cleanerWarning,
            title: "Scan didn’t finish",
            message: store.statusMessage
        ) {
            Button("Try Again") { store.startOrCancelScan() }
            Button("Choose Folders") { store.chooseFolders() }
            Button("Full Disk Access") { store.openFullDiskAccessSettings() }
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

// MARK: - Scan scope (folders + access)

private struct ScanScopePanel: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            }

            DisclosureGroup {
                ScanEvidenceView(store: store)
            } label: {
                Label("Selected Scan Scope", systemImage: "folder").font(.subheadline.weight(.semibold))
            }
        }
        .padding(18)
        .cleanerSurface()
    }
}

private struct PermissionReadinessView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Permissions", systemImage: store.hasPermissionWarnings ? "lock.trianglebadge.exclamationmark" : "checkmark.shield")
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
        case .ready: "checkmark.circle.fill"
        case .advisory: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(for severity: PermissionReadinessItem.Severity) -> Color {
        switch severity {
        case .ready: .cleanerSuccess
        case .advisory: .cleanerInfo
        case .warning: .cleanerWarning
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
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Advanced", systemImage: "slider.horizontal.3")
                .font(.headline)

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
