import Foundation
import LittleTidyCore

let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let fixtureRoot = ProcessInfo.processInfo.environment["LITTLE_TIDY_FIXTURE_ROOT"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? currentDirectory.appendingPathComponent("QA/LittleTidyFixture", isDirectory: true)
let appRoot = fixtureRoot.appendingPathComponent("Applications", isDirectory: true)
let options = ScanOptions(minimumDuplicateSize: 1_000_000, largeFileThreshold: 1_000_000)
let scanner = FileInventoryScanner()

var records: [FileRecord] = []
var summary: ScanSummary?

guard FileManager.default.fileExists(atPath: fixtureRoot.path) else {
    throw QAError.unexpected("Fixture not found at \(fixtureRoot.path). Run ./script/create_qa_fixture.sh first or set LITTLE_TIDY_FIXTURE_ROOT.")
}

for try await event in scanner.scan(request: ScanRequest(roots: [fixtureRoot], options: options)) {
    switch event {
    case .indexedFile(let record):
        records.append(record)
    case .completed(let scanSummary):
        summary = scanSummary
    default:
        break
    }
}

let result = try CleanupAnalysis(
    appUsageAnalyzer: AppUsageAnalyzer(now: { Date().addingTimeInterval(220 * 86_400) })
).analyze(files: records, options: options, appRoots: [appRoot])

let scannedFiles = summary?.scannedFiles ?? records.count
print("scannedFiles=\(scannedFiles)")
print("duplicates=\(result.duplicateGroups.count)")
print("largeFiles=\(result.largeFiles.count)")
print("unusedApps=\(result.unusedApps.count)")

guard scannedFiles >= 5 else {
    throw QAError.unexpected("Expected at least 5 scanned files.")
}
guard result.duplicateGroups.count == 1 else {
    throw QAError.unexpected("Expected exactly 1 duplicate group.")
}
guard result.largeFiles.count >= 4 else {
    throw QAError.unexpected("Expected at least 4 large-file candidates.")
}
guard result.unusedApps.contains(where: { $0.record.bundleIdentifier == "com.federicotrevisani.LittleTidyFixture.OldFixtureApp" }) else {
    throw QAError.unexpected("Expected OldFixtureApp to appear as unused.")
}

let simulatorDevicePath = fixtureRoot.appendingPathComponent("Library/Developer/CoreSimulator/Devices/FIXTURE-DEVICE/data", isDirectory: true)
let simulatorRuntimePath = fixtureRoot.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime", isDirectory: true)
let simulatorJSON = Data(
    """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
          {
            "name": "QA iPhone",
            "udid": "FIXTURE-DEVICE",
            "state": "Shutdown",
            "isAvailable": true,
            "dataPath": "\(simulatorDevicePath.path)"
          }
        ]
      },
      "runtimes": [
        {
          "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
          "name": "iOS 18.4",
          "version": "18.4",
          "isAvailable": true,
          "bundlePath": "\(simulatorRuntimePath.path)"
        }
      ]
    }
    """.utf8
)
let developerInventory = try await DeveloperStorageAnalyzer(
    homeDirectory: fixtureRoot,
    commandRunner: QACommandRunner(output: simulatorJSON)
).analyze()
print("developerItems=\(developerInventory.items.count)")
print("developerBytes=\(developerInventory.items.reduce(Int64(0)) { $0 + $1.bytes })")

for requiredCategory in [
    DeveloperStorageCategory.derivedData,
    .deviceSupport,
    .archives,
    .xctestDevices,
    .simulatorDevices,
    .simulatorRuntimes
] where !developerInventory.items.contains(where: { $0.category == requiredCategory }) {
    throw QAError.unexpected("Expected developer storage category: \(requiredCategory.rawValue)")
}

enum QAError: LocalizedError {
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .unexpected(let message): message
        }
    }
}

private struct QACommandRunner: DeveloperToolCommandRunning {
    let output: Data

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        DeveloperToolCommandResult(standardOutput: output)
    }
}
