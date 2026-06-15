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
                scanActionPanel

                if store.isScanning {
                    ScanProgressCard(store: store)
                }

                if store.scanDidFail {
                    EmptyStateCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: .cleanerWarning,
                        title: "Scan didn’t finish",
                        message: store.statusMessage
                    )
                } else if !hasResults && !store.isScanning {
                    if store.hasCompletedScan {
                        EmptyStateCard(
                            icon: "checkmark.seal.fill",
                            tint: .cleanerSuccess,
                            title: "Nothing to clean up",
                            message: "No duplicates, large files, or unused apps were found in the selected folders."
                        )
                    } else {
                        EmptyStateCard(
                            icon: "sparkles",
                            tint: .accentColor,
                            title: "Ready to scan",
                            message: "Start a scan to find duplicates, large files, and unused apps in your selected folders."
                        )
                    }
                }

                if hasResults {
                    resultsPanel
                }

                scopeAndReadinessPanel

                ScanIssuesView(store: store)

                advancedSettingsPanel

                SafetyNoteView()
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Results")
                    .font(.title2.weight(.semibold))
                Text("Choose a category to inspect candidates before building the cleanup plan.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                SummaryTile(title: "Duplicates", image: "doc.on.doc", bytes: store.reclaimableBytes(for: .duplicate), section: .duplicates, store: store)
                SummaryTile(title: "Large Files", image: "internaldrive", bytes: store.reclaimableBytes(for: .largeFile), section: .largeFiles, store: store)
                SummaryTile(title: "Unused Apps", image: "app.dashed", bytes: store.reclaimableBytes(for: .unusedApp), section: .unusedApps, store: store)
                SummaryTile(title: "Caches", image: "shippingbox", bytes: store.reclaimableBytes(for: .cache), section: .caches, store: store)
            }
        }
    }

    private var scopeAndReadinessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup")
                .font(.title2.weight(.semibold))

            PermissionReadinessView(store: store)

            DisclosureGroup {
                ScanEvidenceView(store: store)
            } label: {
                Label("Selected Scan Scope", systemImage: "folder").font(.headline)
            }
        }
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

private struct EmptyStateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

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

private struct SummaryTile: View {
    let title: String
    let image: String
    let bytes: Int64
    let section: SidebarSection
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        Button {
            store.selectedSection = section
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: image)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.headline)
                Text(ByteCountFormatter.cleanerString(from: bytes))
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cleanerInteractiveSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review \(title), \(ByteCountFormatter.cleanerString(from: bytes)) reclaimable")
        .accessibilityHint("Opens the \(title) review screen.")
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

private struct SafetyNoteView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safety Rules", systemImage: "lock.shield")
                .font(.headline)
            Text("The first version moves selected items to Trash only, excludes system areas by default, and does not remove related app data.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .cleanerSubtleSurface()
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
