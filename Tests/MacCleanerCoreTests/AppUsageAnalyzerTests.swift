import Foundation
import Testing
@testable import MacCleanerCore

@Suite("App usage analyzer")
struct AppUsageAnalyzerTests {
    @Test("reads app bundle metadata and classifies old apps")
    func readsAppMetadata() throws {
        let directory = try TemporaryDirectory()
        let applications = directory.url.appendingPathComponent("Applications", isDirectory: true)
        let app = try createAppBundle(in: applications)

        let oldDate = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: app.path)
        let analyzer = AppUsageAnalyzer(now: { oldDate.addingTimeInterval(200 * 86_400) })

        let records = analyzer.scanApplications(in: [applications])
        let classified = analyzer.classify(records)

        #expect(records.count == 1)
        #expect(records[0].bundleIdentifier == "com.example.app")
        #expect(records[0].displayName == "Example")
        #expect(records[0].version == "1.2.3")
        #expect(classified[0].category == .probablyUnused || classified[0].category == .unknownUsage)
    }

    @Test("prefers Spotlight last-used metadata over filesystem dates")
    func prefersSpotlightLastUsedMetadata() throws {
        let directory = try TemporaryDirectory()
        let applications = directory.url.appendingPathComponent("Applications", isDirectory: true)
        let app = try createAppBundle(in: applications)
        let filesystemDate = Date(timeIntervalSince1970: 1_000_000_000)
        let metadataDate = Date(timeIntervalSince1970: 1_010_000_000)
        try FileManager.default.setAttributes([.modificationDate: filesystemDate], ofItemAtPath: app.path)

        let analyzer = AppUsageAnalyzer(
            now: { metadataDate.addingTimeInterval(10 * 86_400) },
            lastUsedMetadataDate: { url in
                url.standardizedFileURL.path == app.standardizedFileURL.path ? metadataDate : nil
            }
        )

        let record = try #require(analyzer.scanApplications(in: [applications]).first)

        #expect(record.lastOpenedDate == metadataDate)
        #expect(record.confidence == .medium)
    }

    @Test("falls back to filesystem dates when Spotlight metadata is unavailable")
    func fallsBackToFilesystemDatesWithoutMetadata() throws {
        let directory = try TemporaryDirectory()
        let applications = directory.url.appendingPathComponent("Applications", isDirectory: true)
        let app = try createAppBundle(in: applications)
        let filesystemDate = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: filesystemDate], ofItemAtPath: app.path)

        let analyzer = AppUsageAnalyzer(
            now: { filesystemDate.addingTimeInterval(200 * 86_400) },
            lastUsedMetadataDate: { _ in nil }
        )

        let record = try #require(analyzer.scanApplications(in: [applications]).first)

        #expect(record.lastOpenedDate == filesystemDate)
        #expect(record.confidence == .low)
    }

    private func createAppBundle(in applications: URL) throws -> URL {
        let app = applications.appendingPathComponent("Example.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleName": "Example",
            "CFBundleShortVersionString": "1.2.3"
        ]
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try Data(repeating: 1, count: 100).write(to: contents.appendingPathComponent("Executable"))
        return app
    }
}
