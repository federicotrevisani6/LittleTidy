import Foundation
import Testing
@testable import MacCleanerCore

@Suite("Cache analyzer")
struct CacheAnalyzerTests {
    @Test("reports app caches, DerivedData, and dev tool caches above the minimum size")
    func findsCaches() throws {
        let home = try TemporaryDirectory().url

        let safariCache = home.appendingPathComponent("Library/Caches/com.apple.Safari", isDirectory: true)
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        let tinyCache = home.appendingPathComponent("Library/Caches/com.example.tiny", isDirectory: true)
        for directory in [safariCache, derivedData, npmCache, tinyCache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data(repeating: 1, count: 2_000_000).write(to: safariCache.appendingPathComponent("blob.bin"))
        try Data(repeating: 2, count: 3_000_000).write(to: derivedData.appendingPathComponent("build.o"))
        try Data(repeating: 3, count: 1_500_000).write(to: npmCache.appendingPathComponent("pkg.tgz"))
        try Data(repeating: 4, count: 10_000).write(to: tinyCache.appendingPathComponent("small.bin"))

        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)

        // Sorted largest first; tiny cache below the threshold is excluded.
        #expect(candidates.count == 3)
        #expect(candidates.first?.displayName == "Xcode DerivedData")
        #expect(candidates.contains { $0.displayName == "Safari" })
        #expect(candidates.contains { $0.displayName == "npm cache" })
        #expect(!candidates.contains { $0.url == tinyCache })
        #expect(candidates.allSatisfy { $0.sizeBytes >= 1_000_000 })
    }

    @Test("returns nothing when no cache locations exist")
    func emptyWhenAbsent() throws {
        let home = try TemporaryDirectory().url
        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)
        #expect(candidates.isEmpty)
    }
}
