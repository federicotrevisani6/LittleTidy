import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Cache analyzer")
struct CacheAnalyzerTests {
    @Test("reports app caches, DerivedData, and dev tool caches above the minimum size")
    func findsCaches() throws {
        let home = try TemporaryDirectory().url

        let safariCache = home.appendingPathComponent("Library/Caches/com.apple.Safari", isDirectory: true)
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        let cargoCache = home.appendingPathComponent(".cargo/registry/cache", isDirectory: true)
        let uvCache = home.appendingPathComponent(".cache/uv", isDirectory: true)
        let tinyCache = home.appendingPathComponent("Library/Caches/com.example.tiny", isDirectory: true)
        for directory in [safariCache, derivedData, npmCache, cargoCache, uvCache, tinyCache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data(repeating: 1, count: 2_000_000).write(to: safariCache.appendingPathComponent("blob.bin"))
        try Data(repeating: 2, count: 3_000_000).write(to: derivedData.appendingPathComponent("build.o"))
        try Data(repeating: 3, count: 1_500_000).write(to: npmCache.appendingPathComponent("pkg.tgz"))
        try Data(repeating: 4, count: 2_500_000).write(to: cargoCache.appendingPathComponent("cargo.bin"))
        try Data(repeating: 5, count: 1_200_000).write(to: uvCache.appendingPathComponent("uv.bin"))
        try Data(repeating: 6, count: 10_000).write(to: tinyCache.appendingPathComponent("small.bin"))

        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)

        // Sorted largest first; tiny cache below the threshold is excluded.
        #expect(candidates.count == 5)
        #expect(candidates.first?.displayName == "Xcode DerivedData")
        #expect(candidates.contains { $0.displayName == "Safari" })
        #expect(candidates.contains { $0.displayName == "npm cache" })
        #expect(candidates.contains { $0.displayName == "Cargo registry cache" })
        #expect(candidates.contains { $0.displayName == "uv cache" })
        #expect(!candidates.contains { $0.url == tinyCache })
        #expect(candidates.allSatisfy { $0.sizeBytes >= 1_000_000 })
    }

    @Test("finds sandbox caches without offering app documents or Maven artifacts")
    func sandboxCoverage() throws {
        let home = try TemporaryDirectory().url.resolvingSymlinksInPath()
        let cache = home.appendingPathComponent("Library/Containers/com.example.app/Data/Library/Caches")
        let documents = home.appendingPathComponent("Library/Containers/com.example.app/Data/Documents")
        let maven = home.appendingPathComponent(".m2/repository")
        for directory in [cache, documents, maven] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: directory.appendingPathComponent("data"))
        }
        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1)
        #expect(candidates.map { $0.url.resolvingSymlinksInPath().standardized.path } == [cache.resolvingSymlinksInPath().standardized.path])
    }

    @Test("does not offer a symlinked cache target")
    func excludesSymlinks() throws {
        let home = try TemporaryDirectory().url.resolvingSymlinksInPath()
        let caches = home.appendingPathComponent("Library/Caches")
        let documents = home.appendingPathComponent("Documents")
        for directory in [caches, documents] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 8192).write(to: documents.appendingPathComponent("data"))
        try FileManager.default.createSymbolicLink(at: caches.appendingPathComponent("linked"), withDestinationURL: documents)
        #expect(try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1).isEmpty)
    }

    @Test("returns nothing when no cache locations exist")
    func emptyWhenAbsent() throws {
        let home = try TemporaryDirectory().url
        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)
        #expect(candidates.isEmpty)
    }
}
