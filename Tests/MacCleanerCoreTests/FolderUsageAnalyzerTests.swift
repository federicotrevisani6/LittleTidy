import Foundation
import Testing
@testable import MacCleanerCore

@Suite("Folder usage analyzer")
struct FolderUsageAnalyzerTests {
    @Test("aggregates scanned files into first-level folders under each root, largest first")
    func aggregatesByFolder() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("Documents", isDirectory: true)
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        for folder in [photos, projects, projects.appendingPathComponent("App", isDirectory: true)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let big = photos.appendingPathComponent("a.bin")
        let nested = projects.appendingPathComponent("App/b.bin")
        let loose = root.appendingPathComponent("note.txt")
        try Data(repeating: 1, count: 5_000_000).write(to: big)
        try Data(repeating: 2, count: 2_000_000).write(to: nested)
        try Data(repeating: 3, count: 1_000).write(to: loose)

        let records = [try record(for: big), try record(for: nested), try record(for: loose)]
        let usage = FolderUsageAnalyzer().aggregate(files: records, roots: [root])

        // Photos (5 MB), Projects (2 MB, counts the nested file), and the root
        // itself for the loose file — sorted largest first.
        #expect(usage.count == 3)
        #expect(usage[0].name == "Photos")
        #expect(usage[0].bytes == 5_000_000)
        #expect(usage[1].name == "Projects")
        #expect(usage[1].bytes == 2_000_000)
        #expect(usage[1].fileCount == 1)
        #expect(usage.last?.url == root.standardizedFileURL)
    }

    @Test("ignores files outside the provided roots and honors the limit")
    func ignoresOutsideAndLimits() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("Scanned", isDirectory: true)
        let outside = directory.url.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("A", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let inside = root.appendingPathComponent("A/in.bin")
        let external = outside.appendingPathComponent("out.bin")
        try Data(repeating: 1, count: 1_000).write(to: inside)
        try Data(repeating: 2, count: 9_000).write(to: external)

        let usage = FolderUsageAnalyzer().aggregate(
            files: [try record(for: inside), try record(for: external)],
            roots: [root],
            limit: 1
        )

        #expect(usage.count == 1)
        #expect(usage[0].name == "A")
        #expect(!usage.contains { $0.url.path.contains("Elsewhere") })
    }
}
