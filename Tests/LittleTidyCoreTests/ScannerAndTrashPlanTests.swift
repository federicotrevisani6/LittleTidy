import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Scanner and trash plan")
struct ScannerAndTrashPlanTests {
    @Test("scanner skips symlinks by default")
    func scannerSkipsSymlinks() async throws {
        let directory = try TemporaryDirectory()
        let target = directory.url.appendingPathComponent("target.txt")
        let link = directory.url.appendingPathComponent("link.txt")
        try "hello".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        var indexed: [FileRecord] = []
        var skipped: [URL] = []
        let scanner = FileInventoryScanner()
        for try await event in scanner.scan(request: ScanRequest(roots: [directory.url])) {
            switch event {
            case .indexedFile(let record):
                indexed.append(record)
            case .skipped(let url, _):
                skipped.append(url)
            default:
                break
            }
        }

        let indexedPaths = Set(indexed.map { $0.url.standardizedFileURL.path })
        let skippedPaths = Set(skipped.map { $0.standardizedFileURL.path })
        #expect(indexedPaths.contains(target.standardizedFileURL.path))
        #expect(!indexedPaths.contains(link.standardizedFileURL.path))
        #expect(skippedPaths.contains(link.standardizedFileURL.path))
    }

    @Test("scanner blocks system roots unless explicitly included")
    func scannerBlocksSystemRoots() async throws {
        let scanner = FileInventoryScanner()
        var skippedSystemRoot = false

        for try await event in scanner.scan(request: ScanRequest(roots: [URL(fileURLWithPath: "/System")])) {
            if case .skipped(let url, _) = event, url.path == "/System" {
                skippedSystemRoot = true
            }
        }

        #expect(skippedSystemRoot)
    }

    @Test("scanner emits root progress snapshots")
    func scannerEmitsRootProgressSnapshots() async throws {
        let firstDirectory = try TemporaryDirectory()
        let secondDirectory = try TemporaryDirectory()
        try "one".write(to: firstDirectory.url.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: secondDirectory.url.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)

        let scanner = FileInventoryScanner()
        var startedRoots: [URL] = []
        var latestProgress: ScanProgress?

        for try await event in scanner.scan(request: ScanRequest(roots: [firstDirectory.url, secondDirectory.url])) {
            switch event {
            case .rootStarted(let url, _, _):
                startedRoots.append(url)
            case .progress(let progress):
                latestProgress = progress
            default:
                break
            }
        }

        #expect(startedRoots.map(\.standardizedFileURL.path) == [
            firstDirectory.url.standardizedFileURL.path,
            secondDirectory.url.standardizedFileURL.path
        ])
        #expect(latestProgress?.rootCount == 2)
        #expect(latestProgress?.scannedFiles == 2)
    }

    @Test("duplicate trash plan cannot remove every copy in a duplicate group")
    func duplicatePlanCannotRemoveAllCopies() throws {
        let directory = try TemporaryDirectory()
        let first = directory.url.appendingPathComponent("a.bin")
        let second = directory.url.appendingPathComponent("b.bin")
        try Data(repeating: 1, count: 1_100_000).write(to: first)
        try Data(repeating: 1, count: 1_100_000).write(to: second)
        let records = [try record(for: first), try record(for: second)]
        let group = try DuplicateAnalyzer().findDuplicates(in: records, minimumSize: 1_000_000)[0]

        #expect(throws: TrashPlanError.duplicateGroupWouldRemoveAllCopies) {
            _ = try TrashPlanBuilder().buildDuplicatePlan(
                group: group,
                removing: group.files,
                approvedRoots: [directory.url]
            )
        }
    }

    @Test("trash plan rejects files outside approved roots")
    func trashPlanRejectsOutsideRoots() throws {
        let directory = try TemporaryDirectory()
        let otherDirectory = try TemporaryDirectory()
        let file = otherDirectory.url.appendingPathComponent("outside.txt")
        try "outside".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: TrashPlanError.outsideApprovedRoots(file)) {
            _ = try TrashPlanBuilder().buildPlan(
                items: [TrashPlanItem(sourceURL: file, bytes: 7, category: .largeFile, reason: "test")],
                approvedRoots: [directory.url]
            )
        }
    }

    @Test("trash plan rejects symbolic links")
    func trashPlanRejectsSymbolicLinks() throws {
        let directory = try TemporaryDirectory()
        let target = directory.url.appendingPathComponent("target.txt")
        let link = directory.url.appendingPathComponent("link.txt")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: TrashPlanError.symbolicLinkBlocked(link)) {
            _ = try TrashPlanBuilder().buildPlan(
                items: [TrashPlanItem(sourceURL: link, bytes: 6, category: .largeFile, reason: "test")],
                approvedRoots: [directory.url]
            )
        }
    }

    @Test("trash executor skips files that no longer exist")
    func trashExecutorSkipsMissingFiles() {
        let missing = URL(fileURLWithPath: "/tmp/LittleTidyCoreTests-\(UUID().uuidString)-missing")
        let plan = TrashPlan(items: [
            TrashPlanItem(sourceURL: missing, bytes: 10, category: .largeFile, reason: "test")
        ])

        let result = TrashExecutor().execute(plan)

        #expect(result.trashed.isEmpty)
        #expect(result.failed.isEmpty)
        #expect(result.skipped == [missing])
    }

    @Test("trash executor reports source and trash URLs for moved files")
    func trashExecutorReportsSourceAndTrashURLs() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("trash-me.txt")
        try "trash me".write(to: file, atomically: true, encoding: .utf8)
        let plan = TrashPlan(items: [
            TrashPlanItem(sourceURL: file, bytes: 8, category: .largeFile, reason: "test")
        ])

        let result = TrashExecutor().execute(plan)

        #expect(result.failed.isEmpty)
        #expect(result.skipped.isEmpty)
        #expect(result.trashed.count == 1)
        #expect(result.trashed.first?.sourceURL == file)
        #expect(result.trashed.first?.trashURL.path.contains(".Trash") == true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
