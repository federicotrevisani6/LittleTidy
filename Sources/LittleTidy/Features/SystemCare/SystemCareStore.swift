import AppKit
import Observation
import LittleTidyCore
import ServiceManagement

@MainActor
@Observable
final class SystemCareStore {
    var measurements: [StorageMeasurement] = []
    var checks: [ProtectionCheck] = []
    var startup: [StartupEntry] = []
    var snapshots = "Not checked yet."
    var spotlight = "Not checked yet."
    var isScanning = false
    var isPerformingMaintenance = false
    var message: String?
    var assessment: String?
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var scannedAt: Date?
    var helperStatus: SMAppService.Status = .notRegistered
    var helperPayloadAvailable = false
    @ObservationIgnored private let analyzer = SystemCareAnalyzer()
    @ObservationIgnored private let admin = SystemCareAdminClient()
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    func scan() {
        if isScanning { scanTask?.cancel(); return }
        isScanning = true; message = nil
        scanTask = Task {
            defer { isScanning = false; scanTask = nil }
            do {
                let capacity = try URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                totalBytes = Int64(capacity.volumeTotalCapacity ?? 0)
                freeBytes = Int64(capacity.volumeAvailableCapacity ?? 0)
                checks = try await analyzer.protection()
                startup = await analyzer.startupEntries()
                do { snapshots = try await analyzer.localSnapshots() } catch { snapshots = error.localizedDescription }
                do { spotlight = try await analyzer.spotlightStatus() } catch { spotlight = error.localizedDescription }
                // Publish individual measurements as they finish, so a protected
                // or slow location never makes a scan appear stuck.
                measurements = []
                let locations = await analyzer.userLocations + SystemCareAnalyzer.systemLocations
                for location in locations {
                    try Task.checkCancellation()
                    measurements += try await analyzer.storage(locations: [location])
                }
                refreshHelperStatus()
                if helperStatus == .enabled {
                    let privileged = try await admin.measurements()
                    let paths = Set(privileged.map(\.id))
                    measurements.removeAll { paths.contains($0.id) }
                    measurements += privileged
                }
                scannedAt = Date()
            } catch is CancellationError { message = "Scan cancelled. Results shown are partial." }
            catch { message = error.localizedDescription }
        }
    }
    func refreshHelperStatus() { helperStatus = admin.status; helperPayloadAvailable = admin.payloadAvailable }
    func enableAdministratorAccess() {
        do { try admin.register(); refreshHelperStatus(); if helperStatus == .requiresApproval { admin.openApprovalSettings() } }
        catch { message = error.localizedDescription }
    }
    func disableAdministratorAccess() {
        Task { do { try await admin.unregister(); refreshHelperStatus() } catch { message = error.localizedDescription } }
    }
    func openApprovalSettings() { admin.openApprovalSettings() }
    func perform(_ operation: MaintenanceOperation) {
        guard !isPerformingMaintenance else { return }
        isPerformingMaintenance = true; message = nil
        Task {
            defer { isPerformingMaintenance = false }
            do { message = try await admin.maintenance(operation) }
            catch { message = error.localizedDescription }
        }
    }
    func assessApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "Check Application"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        assessment = "Checking \(url.lastPathComponent)…"
        Task {
            do { assessment = try await analyzer.assessApplication(at: url) }
            catch { assessment = "Gatekeeper could not accept this application. This result alone does not identify malware.\n\(error.localizedDescription)" }
        }
    }
    func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "LittleTidy-diagnosis.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = Report(date: Date(), totalBytes: totalBytes, freeBytes: freeBytes, locations: measurements, protection: checks, startup: startup)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
            message = "Report saved to \(url.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }
    private struct Report: Encodable {
        let date: Date; let totalBytes: Int64; let freeBytes: Int64
        let locations: [StorageMeasurement]; let protection: [ProtectionCheck]; let startup: [StartupEntry]
    }
}
