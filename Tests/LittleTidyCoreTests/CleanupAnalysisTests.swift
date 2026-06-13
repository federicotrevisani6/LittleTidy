import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Cleanup analysis")
struct CleanupAnalysisTests {
    @Test("combines duplicate, large-file, and unused-app analysis")
    func combinesAnalysisResults() throws {
        let directory = try TemporaryDirectory()
        let scanRoot = directory.url.appendingPathComponent("Documents", isDirectory: true)
        let appRoot = directory.url.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)

        let duplicateA = scanRoot.appendingPathComponent("duplicate-a.bin")
        let duplicateB = scanRoot.appendingPathComponent("duplicate-b.bin")
        let largeFile = scanRoot.appendingPathComponent("archive.dmg")
        try Data(repeating: 4, count: 1_100_000).write(to: duplicateA)
        try Data(repeating: 4, count: 1_100_000).write(to: duplicateB)
        try Data(repeating: 8, count: 1_500_000).write(to: largeFile)

        let app = appRoot.appendingPathComponent("OldApp.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "OldApp",
            "CFBundleShortVersionString": "1.0"
        ]
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try Data(repeating: 2, count: 100).write(to: contents.appendingPathComponent("OldApp"))

        let records = [
            try record(for: duplicateA),
            try record(for: duplicateB),
            try record(for: largeFile)
        ]

        let result = try CleanupAnalysis(
            appUsageAnalyzer: AppUsageAnalyzer(now: { Date().addingTimeInterval(220 * 86_400) }),
            cacheAnalyzer: CacheAnalyzer(homeDirectory: directory.url)
        ).analyze(
            files: records,
            options: ScanOptions(minimumDuplicateSize: 1_000_000, largeFileThreshold: 1_000_000),
            appRoots: [appRoot]
        )

        #expect(result.duplicateGroups.count == 1)
        #expect(result.largeFiles.map(\.file.url).contains(largeFile))
        #expect(result.unusedApps.map(\.record.bundleIdentifier).contains("com.example.old"))
    }
}
