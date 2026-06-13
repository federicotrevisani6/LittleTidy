import Foundation
import Testing
@testable import MacCleanerCore

@Suite("Duplicate analyzer")
struct DuplicateAnalyzerTests {
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
        #expect(groups[0].reclaimableBytes == 1_100_000)
        #expect(groups[0].recommendedKeep?.url == duplicateB)
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
