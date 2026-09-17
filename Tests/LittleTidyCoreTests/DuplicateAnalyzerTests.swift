import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Duplicate analyzer")
struct DuplicateAnalyzerTests {
    @Test("a disappeared file does not discard readable duplicate groups")
    func toleratesDisappearedFile() throws {
        let directory = try TemporaryDirectory()
        let urls = ["a", "b", "gone"].map { directory.url.appendingPathComponent($0) }
        for url in urls { try Data(repeating: 7, count: 1024).write(to: url) }
        let records = try urls.map { try record(for: $0) }
        try FileManager.default.removeItem(at: urls[2])
        let groups = try DuplicateAnalyzer().findDuplicates(in: records, minimumSize: 1)
        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 2)
    }

    @Test("finds byte-identical duplicate files and recommends one copy to keep")
    func findsDuplicates() throws {
        let directory = try TemporaryDirectory()
        let downloads = directory.url.appendingPathComponent("Downloads", isDirectory: true)
        let documents = directory.url.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let duplicateA = downloads.appendingPathComponent("copy-a.bin")
        let duplicateB = documents.appendingPathComponent("copy-b.bin")
        let unique = documents.appendingPathComponent("unique.bin")
        let duplicateData = Data(repeating: 7, count: 1_100_000)
        try duplicateData.write(to: duplicateA)
        try duplicateData.write(to: duplicateB)
        try Data(repeating: 9, count: 1_100_000).write(to: unique)

        let records = [
            try record(for: duplicateA),
            try record(for: duplicateB),
            try record(for: unique)
        ]

        let groups = try DuplicateAnalyzer().findDuplicates(in: records, minimumSize: 1_000_000)

        #expect(groups.count == 1)
        #expect(groups[0].files.count == 2)
        #expect(groups[0].confidence == .high)
        #expect(groups[0].reclaimableBytes == records[0].storageSize)
        #expect(groups[0].recommendedKeep?.url == duplicateB)
    }

    @Test("does not count hard-linked paths as reclaimable duplicate copies")
    func ignoresHardLinkAliases() throws {
        let directory = try TemporaryDirectory()
        let original = directory.url.appendingPathComponent("original.bin")
        let hardLink = directory.url.appendingPathComponent("hard-link.bin")
        try Data(repeating: 4, count: 1_100_000).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)

        let records = [try record(for: original), try record(for: hardLink)]
        #expect(records[0].fileResourceIdentifier == records[1].fileResourceIdentifier)

        let groups = try DuplicateAnalyzer().findDuplicates(in: records, minimumSize: 1_000_000)
        #expect(groups.isEmpty)
    }

    @Test("reports allocated bytes rather than logical bytes as reclaimable")
    func usesAllocatedSizeForReclaimableBytes() throws {
        let directory = try TemporaryDirectory()
        let first = directory.url.appendingPathComponent("first.bin")
        let second = directory.url.appendingPathComponent("second.bin")
        let data = Data(repeating: 8, count: 2_000_000)
        try data.write(to: first)
        try data.write(to: second)

        let records = [
            FileRecord(url: first, fileSize: 2_000_000, allocatedSize: 1_000_000),
            FileRecord(url: second, fileSize: 2_000_000, allocatedSize: 1_250_000)
        ]
        let group = try #require(DuplicateAnalyzer().findDuplicates(in: records, minimumSize: 1).first)

        #expect(group.reclaimableBytes == records.first(where: { $0.id != group.recommendedKeep?.id })?.storageSize)
    }

    @Test("respects duplicate keep strategies (oldest, newest, prefer non-downloads, shortest path)")
    func respectsDuplicateKeepStrategies() throws {
        let directory = try TemporaryDirectory()
        let downloads = directory.url.appendingPathComponent("Downloads/sub/deep", isDirectory: true)
        let documents = directory.url.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let oldFile = downloads.appendingPathComponent("old.bin")
        let newFile = documents.appendingPathComponent("new.bin")
        let data = Data(repeating: 5, count: 1_100_000)
        try data.write(to: oldFile)
        try data.write(to: newFile)

        let oldRecord = FileRecord(url: oldFile, fileSize: 1_100_000, creationDate: Date(timeIntervalSince1970: 100_000), modificationDate: Date(timeIntervalSince1970: 100_000))
        let newRecord = FileRecord(url: newFile, fileSize: 1_100_000, creationDate: Date(timeIntervalSince1970: 500_000), modificationDate: Date(timeIntervalSince1970: 500_000))

        let analyzer = DuplicateAnalyzer()
        let keepOldest = analyzer.chooseRecommendedKeep(from: [oldRecord, newRecord], strategy: .oldest)
        let keepNewest = analyzer.chooseRecommendedKeep(from: [oldRecord, newRecord], strategy: .newest)
        let keepNonDownloads = analyzer.chooseRecommendedKeep(from: [oldRecord, newRecord], strategy: .preferNonDownloads)
        let keepShortest = analyzer.chooseRecommendedKeep(from: [oldRecord, newRecord], strategy: .shortestPath)

        #expect(keepOldest?.url == oldFile)
        #expect(keepNewest?.url == newFile)
        #expect(keepNonDownloads?.url == newFile)
        #expect(keepShortest?.url == newFile)
    }

    @Test("does not report matching quick fingerprints when full hashes differ")
    func rejectsHashMismatches() throws {
        let directory = try TemporaryDirectory()
        let first = directory.url.appendingPathComponent("first.bin")
        let second = directory.url.appendingPathComponent("second.bin")

        let firstBytes = Data(repeating: 1, count: 1_100_000)
        var secondBytes = firstBytes
        secondBytes[700_000] = 2
        try firstBytes.write(to: first)
        try secondBytes.write(to: second)

        let groups = try DuplicateAnalyzer().findDuplicates(
            in: [try record(for: first), try record(for: second)],
            minimumSize: 1_000_000
        )

        #expect(groups.isEmpty)
    }
}
