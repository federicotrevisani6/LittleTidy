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

enum QAError: LocalizedError {
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .unexpected(let message): message
        }
    }
}
