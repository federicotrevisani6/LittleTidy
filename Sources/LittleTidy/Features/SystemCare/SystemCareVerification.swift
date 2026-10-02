#if DEBUG
import Foundation
import LittleTidyCore

/// Exercises the real signed application's XPC client without changing system
/// settings. This diagnostic entry point is excluded from release builds.
@MainActor
enum SystemCareVerification {
    private struct Report: Encodable {
        let date: Date
        let helperStatus: Int
        let phase: String
        let measurements: [StorageMeasurement]
        let error: String?
    }
    static func run() {
        let client = SystemCareAdminClient()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleTidy/Diagnostics", isDirectory: true)
        let output = directory.appendingPathComponent("admin-verification.json")
        func write(_ phase: String, measurements: [StorageMeasurement] = [], error: String? = nil) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let report = Report(date: Date(), helperStatus: client.status.rawValue, phase: phase, measurements: measurements, error: error)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(report).write(to: output, options: .atomic)
            } catch { NSLog("Administrator verification report failed: %@", error.localizedDescription) }
        }
        write("connecting")
        Task {
            do { write("complete", measurements: try await client.measurements()) }
            catch { write("failed", error: error.localizedDescription) }
        }
    }
}
#endif
