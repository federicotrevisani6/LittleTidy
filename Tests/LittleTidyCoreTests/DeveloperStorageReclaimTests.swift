import Darwin
import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Developer storage reclaim")
struct DeveloperStorageReclaimTests {
    // MARK: XCTest devices

    @Test("policy recommends registered XCTest clones and protects booted ones")
    func xctestPolicy() {
        let policy = DeveloperStoragePolicy()
        let clone = policy.decision(for: .xctestDevices)
        let booted = policy.decision(for: .xctestDevices, isAvailable: true, isActive: true)
        let unverified = policy.unverifiedXCTestDecision()

        #expect(clone.recommendation == .recommended)
        #expect(clone.mechanism == .simctl)
        #expect(booted.recommendation == .protected)
        #expect(booted.mechanism == .simctl)
        #expect(unverified.recommendation == .unclassified)
        #expect(unverified.mechanism == .unsupported)
    }

    @Test("analyzer lists XCTest clones from the simctl testing set and keeps unregistered data unclassified")
    func inventoriesXCTestClones() async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
        let clone = root.appendingPathComponent("CLONE-1/data", isDirectory: true)
        let orphan = root.appendingPathComponent("ORPHAN", isDirectory: true)
        for directory in [clone, orphan] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 1_100_000).write(to: directory.appendingPathComponent("payload.bin"))
        }
        let testingJSON = devicesJSON([
            ("CLONE-1", "Clone 1 of iPhone", "Shutdown", "\(clone.path)"),
            ("CLONE-2", "Clone 2 of iPhone", "Booted", "\(root.path)/CLONE-2/data")
        ])
        let runner = RoutingCommandRunner(routes: [
            "--set testing": testingJSON,
            "simctl list": Data("{\"devices\":{}}".utf8)
        ])

        let inventory = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: runner, homebrewExecutables: []).analyze()
        let xctest = inventory.items.filter { $0.category == .xctestDevices }

        let shutdown = try #require(xctest.first { $0.externalIdentifier == "CLONE-1" })
        #expect(shutdown.recommendation == .recommended)
        #expect(shutdown.cleanupMechanism == .simctl)
        #expect(shutdown.bytes >= 1_100_000)
        let booted = try #require(xctest.first { $0.externalIdentifier == "CLONE-2" })
        #expect(booted.recommendation == .protected)
        #expect(booted.url == nil)
        #expect(xctest.contains { $0.name == "ORPHAN" && $0.recommendation == .unclassified })
    }

    @Test("analyzer falls back to diagnosis-only XCTest data when simctl fails")
    func xctestFallback() async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let inventory = try await DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            homebrewExecutables: []
        ).analyze()

        #expect(inventory.items.contains { $0.category == .xctestDevices && $0.recommendation == .unclassified && $0.url == root })
    }

    @Test("XCTest clone cleanup revalidates and deletes inside the testing device set")
    func deletesXCTestCloneWithTestingSet() async throws {
        let runner = ScriptedRunner(results: [
            DeveloperToolCommandResult(standardOutput: devicesJSON([("CLONE-1", "Clone 1", "Shutdown", "/tmp/none")])),
            DeveloperToolCommandResult(standardOutput: Data())
        ])
        let item = deviceItem(category: .xctestDevices, udid: "CLONE-1")

        let result = await DeveloperStorageCleanupExecutor(
            commandRunner: runner,
            activityChecker: StubActivityChecker(isRunning: false)
        ).execute(items: [item])
        let calls = await runner.calls

        #expect(result.items.first?.status == .removed)
        #expect(calls.first == ["simctl", "--set", "testing", "list", "devices", "--json"])
        #expect(calls.last == ["simctl", "--set", "testing", "delete", "CLONE-1"])
    }

    @Test("XCTest clone that booted after the scan is skipped")
    func skipsBootedXCTestClone() async throws {
        let runner = ScriptedRunner(results: [
            DeveloperToolCommandResult(standardOutput: devicesJSON([("CLONE-1", "Clone 1", "Booted", "/tmp/none")]))
        ])

        let result = await DeveloperStorageCleanupExecutor(
            commandRunner: runner,
            activityChecker: StubActivityChecker(isRunning: false)
        ).execute(items: [deviceItem(category: .xctestDevices, udid: "CLONE-1")])

        #expect(result.items.first?.status == .skipped)
        #expect(await runner.calls.count == 1)
    }

    // MARK: Per-project Xcode guard

    @Test("with Xcode open, build data of a closed project is cleaned and an open one is skipped")
    func perProjectXcodeGuard() async throws {
        let root = try TemporaryDirectory().url
        let closed = root.appendingPathComponent("Closed-abc", isDirectory: true)
        let open = root.appendingPathComponent("Open-def", isDirectory: true)
        for directory in [closed, open] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 1_024).write(to: directory.appendingPathComponent("index.db"))
        }
        let openFile = open.appendingPathComponent("index.db").resolvingSymlinksInPath().path
        let checker = StubActivityChecker(isRunning: true, snapshot: OpenFileSnapshot(paths: [openFile]))
        let decision = DeveloperStoragePolicy().decision(for: .derivedData)

        let result = await DeveloperStorageCleanupExecutor(activityChecker: checker, freeSpace: { nil }).execute(items: [
            trashItem(category: .derivedData, url: closed, decision: decision),
            trashItem(category: .derivedData, url: open, decision: decision)
        ])

        #expect(result.items.map(\.status) == [.removed, .skipped])
        #expect(result.items.last?.message.contains("In use") == true)
        #expect(!FileManager.default.fileExists(atPath: closed.path))
        #expect(FileManager.default.fileExists(atPath: open.path))
    }

    @Test("with Xcode open, a failed open-file snapshot keeps build data blocked")
    func failedSnapshotFailsClosed() async throws {
        let root = try TemporaryDirectory().url
        let project = root.appendingPathComponent("Project-abc", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let result = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: true, snapshot: nil),
            freeSpace: { nil }
        ).execute(items: [trashItem(category: .derivedData, url: project, decision: DeveloperStoragePolicy().decision(for: .derivedData))])

        #expect(result.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: project.path))
    }

    @Test("with Xcode open, data outside the per-project rule still waits for Xcode to quit")
    func otherXcodeDataWaits() async throws {
        let root = try TemporaryDirectory().url
        let support = root.appendingPathComponent("18.4", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let checker = StubActivityChecker(isRunning: true, snapshot: OpenFileSnapshot(paths: ["/unrelated"]))

        let result = await DeveloperStorageCleanupExecutor(activityChecker: checker, freeSpace: { nil }).execute(items: [
            trashItem(category: .deviceSupport, url: support, decision: DeveloperStoragePolicy().decision(for: .deviceSupport))
        ])

        #expect(result.items.first?.status == .skipped)
        #expect(result.items.first?.message.contains("Quit Xcode") == true)
    }

    @Test("open-file snapshot parses lsof name fields and matches whole path components")
    func parsesOpenFileSnapshot() {
        let snapshot = OpenFileSnapshot(lsofOutput: Data("p123\nn/Users/me/DD/App-1/index.db\nnpipe\np456\nn/dev/null\n".utf8))

        #expect(snapshot.paths == ["/Users/me/DD/App-1/index.db", "/dev/null"])
        #expect(snapshot.containsPath(within: URL(fileURLWithPath: "/Users/me/DD/App-1")))
        #expect(!snapshot.containsPath(within: URL(fileURLWithPath: "/Users/me/DD/App")))
    }

    // MARK: Homebrew

    @Test("Homebrew summary parsing uses binary multiples")
    func parsesHomebrewSummary() {
        let dryRun = Data("Would remove: /opt/homebrew/Cellar/foo/1.0 (10 files, 2MB)\n==> This operation would free approximately 8.2GB of disk space.\n".utf8)
        let cleanup = Data("==> This operation has freed approximately 512.5MB of disk space.\n".utf8)

        #expect(HomebrewCleanup.parseReclaimedBytes(dryRun) == Int64(8.2 * 1_073_741_824))
        #expect(HomebrewCleanup.parseReclaimedBytes(cleanup) == Int64(512.5 * 1_048_576))
        #expect(HomebrewCleanup.parseReclaimedBytes(Data("Nothing to clean\n".utf8)) == nil)
    }

    @Test("analyzer reports Homebrew cleanup as a recommended item from the dry run")
    func inventoriesHomebrew() async throws {
        let home = try TemporaryDirectory().url
        let brew = home.appendingPathComponent("brew")
        FileManager.default.createFile(atPath: brew.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let brewRunner = RoutingCommandRunner(routes: [
            "cleanup --dry-run": Data("==> This operation would free approximately 3GB of disk space.\n".utf8)
        ])

        let inventory = try await DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            homebrewExecutables: [brew],
            homebrewRunner: brewRunner
        ).analyze()
        let item = try #require(inventory.items.first { $0.cleanupMechanism == .homebrewCleanup })

        #expect(item.bytes == 3 * 1_073_741_824)
        #expect(item.recommendation == .recommended)
        #expect(item.xcodeActivityRule == .independent)
        #expect(await brewRunner.calls == [HomebrewCleanup.dryRunArguments])
    }

    @Test("Homebrew cleanup refuses an executable outside the standard prefixes")
    func rejectsUnknownBrew() async throws {
        let brewRunner = RoutingCommandRunner(routes: ["cleanup": Data()])
        let decision = DeveloperStoragePolicy().homebrewCleanupDecision()
        let item = DeveloperStorageItem(
            id: "homebrew-cleanup:/tmp/brew", category: .packageCaches, name: "Homebrew", detail: "",
            url: nil, bytes: 10, activity: decision.activity, recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism, consequence: decision.consequence,
            recommendation: decision.recommendation, recommendationReason: decision.reason,
            externalIdentifier: "/tmp/brew"
        )

        let result = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: true),
            homebrewRunner: brewRunner,
            freeSpace: { nil }
        ).execute(items: [item])

        #expect(result.items.first?.status == .skipped)
        #expect(await brewRunner.calls.isEmpty)
    }

    // MARK: Reclaim estimate and verification

    @Test("APFS estimate excludes blocks shared with clones")
    func estimatesClonedStorage() throws {
        let root = try TemporaryDirectory().url
        let source = root.appendingPathComponent("source", isDirectory: true)
        let cloneFolder = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloneFolder, withIntermediateDirectories: true)
        let original = source.appendingPathComponent("disk.img")
        try Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: original)
        guard clonefile(original.path, cloneFolder.appendingPathComponent("disk.img").path, 0) == 0 else {
            return // Not an APFS volume; the estimator returns nil there.
        }
        try Data(repeating: 9, count: 1_000_000).write(to: cloneFolder.appendingPathComponent("unique.bin"))

        let estimate = try #require(APFSReclaimEstimator().minimumReclaimableBytes(at: cloneFolder))

        #expect(estimate >= 1_000_000)
        #expect(estimate < 2_000_000)
    }

    @Test("result reports measured free space and bytes still in the Trash")
    func reportsVerification() async throws {
        let root = try TemporaryDirectory().url
        let project = root.appendingPathComponent("Project-abc", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let readings = FreeSpaceReadings([1_000, 1_600])

        let result = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: false),
            freeSpace: { readings.next() }
        ).execute(items: [trashItem(category: .derivedData, url: project, decision: DeveloperStoragePolicy().decision(for: .derivedData))])

        #expect(result.measuredFreedBytes == 600)
        #expect(result.bytesInTrash == 1_024)
        #expect(result.items.first?.movedToTrash == true)
    }

    @Test("removed bytes use the guaranteed reclaimable size of cloned devices")
    func removedBytesUseGuaranteedSize() {
        let item = deviceItem(category: .xctestDevices, udid: "CLONE-1").withMinimumReclaimableBytes(400)

        #expect(item.guaranteedReclaimableBytes == 400)
        #expect(item.hasSharedStorage == false) // 1,600 shared bytes is below the 1 MB display threshold
        #expect(DeveloperStorageInventory(items: [item], simulatorToolAvailable: true).guaranteedReclaimableBytes(for: .recommended) == 400)
    }

    // MARK: Helpers

    private func devicesJSON(_ devices: [(udid: String, name: String, state: String, dataPath: String)]) -> Data {
        let entries = devices.map {
            "{\"udid\":\"\($0.udid)\",\"name\":\"\($0.name)\",\"state\":\"\($0.state)\",\"isAvailable\":true,\"dataPath\":\"\($0.dataPath)\"}"
        }
        return Data("{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-2\":[\(entries.joined(separator: ","))]}}".utf8)
    }

    private func deviceItem(category: DeveloperStorageCategory, udid: String) -> DeveloperStorageItem {
        let decision = DeveloperStoragePolicy().decision(for: category)
        return DeveloperStorageItem(
            id: "\(category.rawValue):\(udid)", category: category, name: udid, detail: "Shutdown",
            url: nil, bytes: 2_000, activity: decision.activity, recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism, consequence: decision.consequence,
            recommendation: decision.recommendation, recommendationReason: decision.reason,
            externalIdentifier: udid
        )
    }

    private func trashItem(category: DeveloperStorageCategory, url: URL, decision: DeveloperStorageDecision) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: "path:\(url.path)", category: category, name: url.lastPathComponent, detail: "",
            url: url, bytes: 1_024, activity: decision.activity, recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism, consequence: decision.consequence,
            recommendation: decision.recommendation, recommendationReason: decision.reason
        )
    }
}

/// Returns the output of the first route whose key appears in the joined
/// arguments; unmatched commands fail like an unavailable tool.
private actor RoutingCommandRunner: DeveloperToolCommandRunning {
    private let routes: [(String, Data)]
    private(set) var calls: [[String]] = []

    init(routes: KeyValuePairs<String, Data>) {
        self.routes = routes.map { ($0.key, $0.value) }
    }

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        calls.append(arguments)
        let joined = arguments.joined(separator: " ")
        guard let output = routes.first(where: { joined.contains($0.0) })?.1 else {
            throw DeveloperToolCommandError.unavailable(executable.path)
        }
        return DeveloperToolCommandResult(standardOutput: output)
    }
}

private actor ScriptedRunner: DeveloperToolCommandRunning {
    private var results: [DeveloperToolCommandResult]
    private(set) var calls: [[String]] = []

    init(results: [DeveloperToolCommandResult]) {
        self.results = results
    }

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        calls.append(arguments)
        guard !results.isEmpty else { throw DeveloperToolCommandError.unavailable(executable.path) }
        return results.removeFirst()
    }
}

private struct StubActivityChecker: DeveloperToolActivityChecking {
    let isRunning: Bool
    var snapshot: OpenFileSnapshot?

    func isXcodeRunning() async -> Bool { isRunning }
    func openFileSnapshot() async -> OpenFileSnapshot? { snapshot }
}

private final class FreeSpaceReadings: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64]

    init(_ values: [Int64]) {
        self.values = values
    }

    func next() -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty ? nil : values.removeFirst()
    }
}
