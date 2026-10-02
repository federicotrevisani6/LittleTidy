import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Git worktree safety")
struct GitWorktreeTests {
    @Test("Discovery finds registered linked worktrees, protects the main checkout, and respects roots")
    func discovery() async throws {
        let fixture = try await GitWorktreeFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let other = fixture.root.appendingPathComponent("outside")
        try await fixture.git(["worktree", "add", "-b", "outside", other.path])
        let linkedOnly = GitWorktreeManager(root: fixture.linked, activity: TestWorktreeActivity())
        let found = try await linkedOnly.discover()
        #expect(found.worktrees.map(\.path) == [fixture.linked.path])
        #expect(found.issues.isEmpty)
        let all = try await GitWorktreeManager(root: fixture.root, activity: TestWorktreeActivity()).discover()
        #expect(Set(all.worktrees.map(\.path)) == [fixture.linked.path, other.path])
        #expect(!all.worktrees.contains { $0.path == fixture.main.path })
        let redirect = fixture.root.appendingPathComponent("redirect")
        try FileManager.default.createSymbolicLink(at: redirect, withDestinationURL: fixture.linked)
        await #expect(throws: (any Error).self) { try await GitWorktreeManager(root: redirect).discover() }
    }

    @Test("Dirty, untracked, ignored, locked, detached, and hidden-index worktrees stay protected")
    func valuableDataIsProtected() async throws {
        let fixture = try await GitWorktreeFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = GitWorktreeManager(root: fixture.root, activity: TestWorktreeActivity())
        let record = try #require(try await manager.discover().worktrees.first)
        let local = fixture.linked.appendingPathComponent("local.txt")
        try Data("uncommitted".utf8).write(to: local)
        let untracked = try await manager.inspect(record)
        #expect(!untracked.canRemove)
        #expect(untracked.changes.contains { $0.contains("local.txt") })
        await #expect(throws: (any Error).self) { try await manager.remove(untracked, allowPermanentDeletion: true, ownerStoppedConfirmed: true) }
        #expect(try Data(contentsOf: local) == Data("uncommitted".utf8))
        try FileManager.default.removeItem(at: local)
        let ignored = fixture.linked.appendingPathComponent("ignored.txt")
        try Data("personal ignored data".utf8).write(to: ignored)
        let ignoredCheck = try await manager.inspect(record)
        #expect(!ignoredCheck.canRemove)
        #expect(ignoredCheck.changes.contains { $0.hasPrefix("!! ") && $0.contains("ignored.txt") })
        try FileManager.default.removeItem(at: ignored)
        try await fixture.git(["worktree", "lock", fixture.linked.path])
        #expect(!(try await manager.inspect(record)).canRemove)
        try await fixture.git(["worktree", "unlock", fixture.linked.path])
        try await fixture.git(["-C", fixture.linked.path, "update-index", "--assume-unchanged", "tracked.txt"])
        try Data("hidden changes".utf8).write(to: fixture.linked.appendingPathComponent("tracked.txt"))
        #expect(!(try await manager.inspect(record)).canRemove)
        try await fixture.git(["-C", fixture.linked.path, "update-index", "--no-assume-unchanged", "tracked.txt"])
        #expect(!(try await manager.inspect(record)).canRemove)
        try await fixture.git(["-C", fixture.linked.path, "restore", "tracked.txt"])
        try await fixture.git(["-C", fixture.linked.path, "checkout", "--detach"])
        #expect(!(try await manager.inspect(record)).canRemove)
    }

    @Test("Inspection does not execute content filters configured by the repository")
    func filtersNeverExecute() async throws {
        let fixture = try await GitWorktreeFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sentinel = fixture.root.appendingPathComponent("filter-ran")
        try await fixture.git(["config", "filter.danger.clean", "touch " + sentinel.path])
        try Data("tracked.txt filter=danger\n".utf8).write(to: fixture.linked.appendingPathComponent(".gitattributes"))
        try Data("modified".utf8).write(to: fixture.linked.appendingPathComponent("tracked.txt"))
        let manager = GitWorktreeManager(root: fixture.root, activity: TestWorktreeActivity())
        let record = try #require(try await manager.discover().worktrees.first)
        let checked = try await manager.inspect(record)
        #expect(!checked.canRemove)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        await #expect(throws: (any Error).self) { try await manager.remove(checked, allowPermanentDeletion: true, ownerStoppedConfirmed: true) }
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("Removal rechecks data and activity, requires opt-in, and preserves the branch and main checkout")
    func removalLifecycle() async throws {
        let fixture = try await GitWorktreeFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let activity = TestWorktreeActivity()
        let manager = GitWorktreeManager(root: fixture.root, activity: activity)
        let record = try #require(try await manager.discover().worktrees.first)
        let checked = try await manager.inspect(record)
        #expect(checked.canRemove)
        await #expect(throws: (any Error).self) { try await manager.remove(checked, allowPermanentDeletion: false, ownerStoppedConfirmed: true) }
        await #expect(throws: (any Error).self) { try await manager.remove(checked, allowPermanentDeletion: true, ownerStoppedConfirmed: false) }
        await activity.setReason("Activity could not be verified")
        await #expect(throws: (any Error).self) { try await manager.remove(checked, allowPermanentDeletion: true, ownerStoppedConfirmed: true) }
        await activity.setReason(nil)
        let later = fixture.linked.appendingPathComponent("later.txt")
        try Data("arrived after review".utf8).write(to: later)
        await #expect(throws: (any Error).self) { try await manager.remove(checked, allowPermanentDeletion: true, ownerStoppedConfirmed: true) }
        #expect(try Data(contentsOf: later) == Data("arrived after review".utf8))
        try FileManager.default.removeItem(at: later)
        try await manager.remove(checked, allowPermanentDeletion: true, ownerStoppedConfirmed: true)
        #expect(!FileManager.default.fileExists(atPath: fixture.linked.path))
        #expect(try Data(contentsOf: fixture.main.appendingPathComponent("tracked.txt")) == Data("committed content".utf8))
        let branch = try await fixture.git(["rev-parse", "refs/heads/agent-test"])
        #expect(String(decoding: branch, as: UTF8.self).trimmingCharacters(in: .newlines) == record.head)
        #expect(try await manager.discover().worktrees.isEmpty)
    }
}

private actor TestWorktreeActivity: WorktreeActivityChecking {
    private var reason: String?
    func setReason(_ reason: String?) { self.reason = reason }
    func blockingReason(at path: String) async -> String? { reason }
}

private struct GitWorktreeFixture {
    let root: URL
    var main: URL { root.appendingPathComponent("main") }
    var linked: URL { root.appendingPathComponent("agent worktree") }
    private let runner = BoundedCommandRunner(timeout: 15, environment: ["PATH": "/usr/bin:/bin", "HOME": "/nonexistent", "GIT_CONFIG_NOSYSTEM": "1"])
    static func make() async throws -> Self {
        let fixture = Self(root: URL(fileURLWithPath: "/private/tmp/LittleTidyWorktreeTests-\(UUID().uuidString)"))
        try FileManager.default.createDirectory(at: fixture.main, withIntermediateDirectories: true)
        try await fixture.git(["init", "-b", "main"])
        try Data("committed content".utf8).write(to: fixture.main.appendingPathComponent("tracked.txt"))
        try Data("ignored.txt\n".utf8).write(to: fixture.main.appendingPathComponent(".gitignore"))
        try await fixture.git(["add", "."])
        try await fixture.git(["-c", "user.name=LittleTidy Test", "-c", "user.email=test@example.invalid", "commit", "-m", "Fixture"])
        try await fixture.git(["worktree", "add", "-b", "agent-test", fixture.linked.path])
        return fixture
    }
    @discardableResult func git(_ arguments: [String]) async throws -> Data {
        try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["-C", main.path, "-c", "core.hooksPath=/dev/null"] + arguments).standardOutput
    }
}
