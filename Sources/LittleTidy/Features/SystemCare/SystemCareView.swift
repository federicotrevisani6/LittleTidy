import AppKit
import LittleTidyCore
import ServiceManagement
import SwiftUI

struct SystemCareView: View {
    let section: SidebarSection
    let store: SystemCareStore
    @State private var exploredLocation: StorageLocation?
    @State private var showingWorktrees = false
    @State private var pendingMaintenance: MaintenanceOperation?
    @State private var confirmingMaintenance = false
    @State private var confirmingAdministratorAccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SystemCareHeader(section: section, store: store)
                if let message = store.message {
                    Text(message).font(.callout).textSelection(.enabled).padding(12).cleanerSubtleSurface()
                }
                switch section {
                case .systemDiagnosis:
                    Button("Agent Worktrees…", systemImage: "point.3.connected.trianglepath.dotted") { showingWorktrees = true }
                    SystemDiagnosisView(store: store, exploredLocation: $exploredLocation)
                case .maintenance: SystemMaintenanceView(store: store, pendingMaintenance: $pendingMaintenance, confirmingMaintenance: $confirmingMaintenance)
                case .protection: SystemProtectionView(store: store)
                default: EmptyView()
                }
                AdministratorAccessView(store: store, confirmingAdministratorAccess: $confirmingAdministratorAccess)
            }.padding(24)
        }
        .onAppear { store.refreshHelperStatus() }
        .sheet(isPresented: $showingWorktrees) { WorktreeReviewView() }
        .sheet(item: $exploredLocation) { location in StorageFolderBrowser(root: location) }
        .confirmationDialog("Allow administrator access?", isPresented: $confirmingAdministratorAccess, titleVisibility: .visible) {
            Button("Enable Administrator Access") { store.enableAdministratorAccess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LittleTidy installs a signed background service to measure protected storage and run the maintenance tasks shown here. Approve it in macOS Login Items & Extensions. You can remove it below at any time.")
        }
        .confirmationDialog(pendingMaintenance?.title ?? "Run maintenance?", isPresented: $confirmingMaintenance, titleVisibility: .visible) {
            Button("Run Maintenance") { if let operation = pendingMaintenance { store.perform(operation) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(pendingMaintenance?.explanation ?? "") }
    }
}

private struct SystemCareHeader: View {
    let section: SidebarSection
    let store: SystemCareStore
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(section.title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary).font(.callout)
                if let date = store.scannedAt {
                    Text("Last scan: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(store.isScanning ? "Cancel" : "Scan Mac", systemImage: store.isScanning ? "xmark.circle" : "arrow.clockwise", action: store.scan)
                .buttonStyle(.borderedProminent)
            Button("Export Report", systemImage: "square.and.arrow.up", action: store.exportReport)
                .disabled(store.scannedAt == nil || store.isScanning)
        }
    }
    private var subtitle: String {
        switch section {
        case .systemDiagnosis: "Understand app data, developer resources, and protected system storage."
        case .maintenance: "Troubleshoot search and network issues, review startup services, and check local backups."
        case .protection: "Check the protections built into macOS and assess an application's trust."
        default: ""
        }
    }
}

private struct SystemDiagnosisView: View {
    let store: SystemCareStore
    @Binding var exploredLocation: StorageLocation?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.totalBytes > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(ByteCountFormatter.cleanerString(from: store.freeBytes)) free").font(.title3.bold())
                        Spacer()
                        Text("\(ByteCountFormatter.cleanerString(from: store.totalBytes)) total").foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(max(0, store.totalBytes - store.freeBytes)), total: Double(store.totalBytes))
                    Text("Folder measurements can overlap. APFS clones, compressed files, mounted images, and purgeable storage can differ from physical disk usage. These rows are not a reclaimable-space total.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).cleanerSurface()
            }
            if store.measurements.isEmpty && !store.isScanning {
                ContentUnavailableView("Find what uses your disk", systemImage: "internaldrive", description: Text("Scan Mac to measure known storage locations and identify access gaps."))
            }
            ForEach(store.measurements.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }) { measurement in
                StorageMeasurementRow(measurement: measurement, exploredLocation: $exploredLocation)
            }
            if store.isScanning { ProgressView("Measuring storage…").frame(maxWidth: .infinity) }
        }
    }
}

private struct SystemMaintenanceView: View {
    let store: SystemCareStore
    @Binding var pendingMaintenance: MaintenanceOperation?
    @Binding var confirmingMaintenance: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MaintenanceOperation.allCases, id: \.self) { operation in
                MaintenanceOperationRow(operation: operation, store: store, pendingMaintenance: $pendingMaintenance, confirmingMaintenance: $confirmingMaintenance)
            }
            if store.helperStatus != .enabled {
                Text("Enable Administrator Access to run these tasks.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Maintenance targets specific problems; it is not a routine speed boost.")
                .font(.caption).foregroundStyle(.secondary)
            MaintenanceStatusCard(title: "Spotlight", detail: store.spotlight)
            MaintenanceStatusCard(title: "Time Machine local snapshots", detail: store.snapshots)
            HStack {
                Button("Open Disk Utility", systemImage: "externaldrive") { openApplication("com.apple.DiskUtility") }
                Button("Software Update", systemImage: "arrow.down.circle") { openURL("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
                Button("Login Items & Extensions", systemImage: "switch.2") { store.openApprovalSettings() }
            }
            Text("Startup services").font(.headline)
            Text("Review background components below. Manage them in Login Items & Extensions or uninstall their owning app; deleting a plist can break an application.").font(.caption).foregroundStyle(.secondary)
            ForEach(store.startup) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.callout.bold())
                        Text(entry.executable ?? entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let issue = entry.issue { Text(issue).font(.caption).foregroundStyle(Color.cleanerWarning) }
                    }
                    Spacer()
                    Text(entry.isSystemWide ? "System-wide" : "Your account").font(.caption).foregroundStyle(.secondary)
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                }.padding(12).cleanerSubtleSurface()
            }
        }
    }
    private func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
    private func openApplication(_ id: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

private struct SystemProtectionView: View {
    let store: SystemCareStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.state == .enabled ? "checkmark.shield.fill" : check.state == .attention ? "exclamationmark.shield.fill" : "questionmark.circle")
                        .foregroundStyle(check.state == .enabled ? Color.cleanerSuccess : Color.cleanerWarning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(check.name).font(.headline)
                        Text(check.state == .enabled ? "Enabled" : check.state == .attention ? "Review recommended" : "Status unknown").font(.caption.bold())
                        Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Settings") { openURL(check.settingsURL) }
                }.padding(16).cleanerSurface()
            }
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Application trust check").font(.headline)
                    Text("Assess an app using Apple's Gatekeeper policy. Rejection may mean an unsigned or unnotarized app; it does not by itself mean malware.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose App…", action: store.assessApplication)
            }.padding(16).cleanerSurface()
            if let assessment = store.assessment { Text(assessment).font(.callout).textSelection(.enabled).padding(12).cleanerSubtleSurface() }
            Text("These checks describe macOS security settings and app trust. LittleTidy does not yet provide a malware engine, real-time threat monitoring, or a guarantee that the Mac is free of malware.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
    private func openApplication(_ id: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

private struct AdministratorAccessView: View {
    let store: SystemCareStore
    @Binding var confirmingAdministratorAccess: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Label("Administrator Access", systemImage: "lock.shield").font(.headline)
                Text(adminDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.helperStatus == .enabled {
                Button("Remove Service", action: store.disableAdministratorAccess)
            } else if store.helperStatus == .requiresApproval {
                Button("Approve in Settings", action: store.openApprovalSettings)
            } else {
                Button("Enable…") { confirmingAdministratorAccess = true }
                    .disabled(!store.helperPayloadAvailable)
            }
            Button("Refresh", action: store.refreshHelperStatus)
        }.padding(16).cleanerSurface()
    }
    private var adminDescription: String {
        switch store.helperStatus {
        case .enabled: "Enabled. Protected storage measurements and maintenance are available."
        case .requiresApproval: "Approval is required in macOS Login Items & Extensions."
        case .notFound: store.helperPayloadAvailable
            ? "Not enabled. Approve the background service to measure protected storage and run maintenance."
            : "This build does not include the administrator service. Install the complete app."
        default: "Optional. Full Disk Access and administrator privileges are separate permissions."
        }
    }
}

private struct StorageMeasurementRow: View {
    let measurement: StorageMeasurement
    @Binding var exploredLocation: StorageLocation?
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(measurement.location.name).font(.headline)
                Text(measurement.location.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(measurement.location.explanation).font(.caption).foregroundStyle(.secondary)
                if let issue = measurement.issue {
                    Text("Size unknown · \(issue)").font(.caption).foregroundStyle(Color.cleanerWarning).lineLimit(3).help(issue).textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Text(measurement.bytes.map { ByteCountFormatter.cleanerString(from: $0) } ?? "Unknown")
                    .font(.callout.bold().monospacedDigit())
                Button("Explore…") { exploredLocation = measurement.location }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: measurement.location.path)]) }
            }
        }.padding(16).cleanerSurface()
    }
}

private struct MaintenanceOperationRow: View {
    let operation: MaintenanceOperation
    let store: SystemCareStore
    @Binding var pendingMaintenance: MaintenanceOperation?
    @Binding var confirmingMaintenance: Bool
    var body: some View {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(operation.title).font(.headline)
                        Text(operation.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run…") { pendingMaintenance = operation; confirmingMaintenance = true }
                        .disabled(store.isPerformingMaintenance || store.helperStatus != .enabled)
                }.padding(16).cleanerSurface()
    }
}

private struct MaintenanceStatusCard: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cleanerSurface()
        .accessibilityElement(children: .combine)
    }
}
