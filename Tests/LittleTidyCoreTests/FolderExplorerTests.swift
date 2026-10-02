import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Read-only storage exploration")
struct FolderExplorerTests {
    @Test("Exploration rejects outside roots, redirected parents, and device mounts")
    func respectsBoundaries() async throws {
        let fixture = try TemporaryDirectory().url
        let root = fixture.appendingPathComponent("approved")
        let outside = fixture.appendingPathComponent("approved-other")
        let device = root.appendingPathComponent("CoreDevice/device")
        for url in [root, outside, device] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let link = root.appendingPathComponent("redirect")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let explorer = FolderExplorer(allowedRoots: [root])
        for url in [outside, link, link.appendingPathComponent("nested"), device] {
            await #expect(throws: (any Error).self) { try await explorer.list(at: url) }
        }
        let listing = try await explorer.list(at: root)
        #expect(listing.entries.count == 2)
        #expect(listing.entries.allSatisfy { $0.kind == .protected && !$0.canExplore })
        for entry in listing.entries {
            let measured = try await explorer.measure(entry)
            #expect(measured.bytes == nil)
        }
    }
    @Test("Metadata distinguishes worktrees and build output without treating arbitrary Caches folders as disposable")
    func classifiesEvidence() async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("projects")
        let repo = root.appendingPathComponent("repo")
        let worktree = root.appendingPathComponent("worktree")
        let fakeCache = root.appendingPathComponent("Caches")
        let build = repo.appendingPathComponent(".build")
        let knownCache = home.appendingPathComponent("Library/Caches/example")
        for url in [repo.appendingPathComponent(".git"), worktree, fakeCache, build, knownCache] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try Data("gitdir: /never-read/external/git/worktrees/example\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        try Data("// fixture manifest".utf8).write(to: repo.appendingPathComponent("Package.swift"))
        let explorer = FolderExplorer(allowedRoots: [root, home.appendingPathComponent("Library/Caches")], home: home)
        let listing = try await explorer.list(at: root)
        #expect(listing.entries.count == 3) // Only immediate children.
        #expect(listing.entries.first { $0.name == "repo" }?.kind == .gitRepository)
        #expect(listing.entries.first { $0.name == "worktree" }?.kind == .gitWorktree)
        #expect(listing.entries.first { $0.name == "Caches" }?.kind == .unclassified)
        let children = try await explorer.list(at: repo)
        #expect(children.entries.first { $0.name == ".build" }?.kind == .buildOutput)
        let caches = try await explorer.list(at: home.appendingPathComponent("Library/Caches"))
        #expect(caches.entries.first?.kind == .cache)
    }
    @Test("Measures real content and refuses a directory swapped for a symbolic link")
    func revalidatesBeforeMeasuring() async throws {
        let root = try TemporaryDirectory().url
        let data = root.appendingPathComponent("documents")
        let outside = try TemporaryDirectory().url
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 16384).write(to: data.appendingPathComponent("valuable.txt"))
        let explorer = FolderExplorer(allowedRoots: [root])
        let entry = try #require(try await explorer.list(at: root).entries.first)
        let measured = try await explorer.measure(entry)
        #expect((measured.bytes ?? 0) >= 16384)
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("valuable.txt").path))
        try FileManager.default.moveItem(at: data, to: root.appendingPathComponent("retained"))
        try FileManager.default.createSymbolicLink(at: data, withDestinationURL: outside)
        await #expect(throws: (any Error).self) { try await explorer.measure(entry) }
    }
}
