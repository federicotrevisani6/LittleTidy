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

        let inventory = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: runner, agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []).analyze()
        let xctest = inventory.items.filter { $0.category == .xctestDevices }

        // CLONE-2 is booted, so a test session is active and CLONE-1 is protected too.
        let shutdown = try #require(xctest.first { $0.externalIdentifier == "CLONE-1" })
        #expect(shutdown.recommendation == .protected)
        #expect(shutdown.activity == .active)
        #expect(shutdown.recommendationReason.contains("test session"))
        #expect(shutdown.bytes >= 1_100_000)
        let booted = try #require(xctest.first { $0.externalIdentifier == "CLONE-2" })
        #expect(booted.recommendation == .protected)
        #expect(booted.url == nil)
        #expect(xctest.contains { $0.name == "ORPHAN" && $0.recommendation == .unclassified })
    }

    @Test("analyzer recommends shutdown clones only when every clone of the set is shut down",
          arguments: [("Shutdown", StorageRecommendation.recommended), ("Creating", .protected), ("Booting", .protected)])
    func recommendsClonesOnlyWhenSetIsIdle(otherState: String, expected: StorageRecommendation) async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("CLONE-1/data"), withIntermediateDirectories: true)
        let runner = RoutingCommandRunner(routes: [
            "--set testing": devicesJSON([
                ("CLONE-1", "Clone 1", "Shutdown", "\(root.path)/CLONE-1/data"),
                ("CLONE-2", "Clone 2", otherState, "\(root.path)/CLONE-2/data")
            ])
        ])

        let inventory = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: runner, agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []).analyze()

        #expect(inventory.items.first { $0.externalIdentifier == "CLONE-1" }?.recommendation == expected)
    }

    @Test("analyzer falls back to diagnosis-only XCTest data when simctl fails")
    func xctestFallback() async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let inventory = try await DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []
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

    @Test("XCTest clone is skipped when another clone of the set booted after the scan")
    func skipsCloneDuringActiveTestSession() async throws {
        let runner = ScriptedRunner(results: [
            DeveloperToolCommandResult(standardOutput: devicesJSON([
                ("CLONE-1", "Clone 1", "Shutdown", "/tmp/none"),
                ("CLONE-2", "Clone 2", "Booted", "/tmp/none")
            ]))
        ])

        let result = await DeveloperStorageCleanupExecutor(
            commandRunner: runner,
            activityChecker: StubActivityChecker(isRunning: false)
        ).execute(items: [deviceItem(category: .xctestDevices, udid: "CLONE-1")])

        #expect(result.items.first?.status == .skipped)
        #expect(result.items.first?.message.contains("test session") == true)
        #expect(await runner.calls.count == 1)
    }

    @Test("XCTest clone is skipped without calling simctl while xcodebuild runs")
    func skipsCloneWhileXcodebuildRuns() async throws {
        let runner = ScriptedRunner(results: [])

        let result = await DeveloperStorageCleanupExecutor(
            commandRunner: runner,
            activityChecker: StubActivityChecker(isRunning: false, xcodebuildRunning: true)
        ).execute(items: [deviceItem(category: .xctestDevices, udid: "CLONE-1")])

        #expect(result.items.first?.status == .skipped)
        #expect(result.items.first?.message.contains("xcodebuild") == true)
        #expect(await runner.calls.isEmpty)
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

    // MARK: Snapshots and DerivedData names

    @Test("local snapshot parser reads Time Machine names in local time and ignores other lines")
    func parsesLocalSnapshots() throws {
        let output = Data("Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-24-180741.local\ncom.apple.TimeMachine.2026-10-24-190450.local\ncom.example.other.local\n".utf8)
        let utc = try #require(TimeZone(identifier: "UTC"))

        let dates = LocalSnapshotInventory.parseSnapshotDates(output, timeZone: utc)

        #expect(dates.count == 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let latest = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: try #require(dates.last))
        #expect([latest.year, latest.month, latest.day, latest.hour, latest.minute, latest.second] == [2026, 10, 24, 19, 4, 50])
    }

    @Test("analyzer records the latest local snapshot and names DerivedData projects without info.plist")
    func snapshotAndProjectNames() async throws {
        let home = try TemporaryDirectory().url
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        for name in ["PetroCheck-eyucodwfauvormaistxbodcopolj/SourcePackages", "ModuleCache.noindex", "Short-abc"] {
            try FileManager.default.createDirectory(at: derivedData.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let runner = RoutingCommandRunner(routes: [
            "listlocalsnapshots": Data("com.apple.TimeMachine.2026-10-24-180741.local\ncom.apple.TimeMachine.2026-10-24-190450.local\n".utf8)
        ])

        let inventory = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: runner, agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []).analyze()
        let derived = inventory.items.filter { $0.category == .derivedData }

        #expect(inventory.latestLocalSnapshotAt == LocalSnapshotInventory.parseSnapshotDates(Data("com.apple.TimeMachine.2026-10-24-190450.local".utf8)).first)
        #expect(derived.contains { $0.name == "PetroCheck" && $0.detail.hasPrefix("Build data for PetroCheck") })
        #expect(derived.contains { $0.name == "ModuleCache.noindex" && $0.detail == "Shared Xcode build data" })
        #expect(derived.contains { $0.name == "Short-abc" && $0.detail == "Shared Xcode build data" })
    }

    @Test("analyzer reports no snapshot when tmutil is unavailable")
    func noSnapshotWhenTmutilFails() async throws {
        let home = try TemporaryDirectory().url

        let inventory = try await DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []
        ).analyze()

        #expect(inventory.latestLocalSnapshotAt == nil)
    }

    // MARK: Snapshot release

    @Test("snapshot release thins through tmutil with the requested amount and reports the outcome")
    func releasesSnapshotSpace() async throws {
        let two = Data("com.apple.TimeMachine.2026-10-24-180741.local\ncom.apple.TimeMachine.2026-10-24-190450.local\n".utf8)
        let one = Data("com.apple.TimeMachine.2026-10-24-190450.local\n".utf8)
        let runner = ScriptedRunner(results: [
            DeveloperToolCommandResult(standardOutput: two),
            DeveloperToolCommandResult(standardOutput: Data()),
            DeveloperToolCommandResult(standardOutput: one)
        ])
        let readings = FreeSpaceReadings([1_000, 5_000])

        let result = try await LocalSnapshotReleaser(runner: runner, freeSpace: { readings.next() }).release(bytes: 4_000)
        let calls = await runner.calls

        #expect(calls == [["listlocalsnapshots", "/"], ["thinlocalsnapshots", "/", "4000", "4"], ["listlocalsnapshots", "/"]])
        #expect(result.snapshotsRemoved == 1)
        #expect(result.measuredFreedBytes == 4_000)
    }

    @Test("snapshot release refuses a zero amount without running tmutil")
    func refusesEmptyRelease() async throws {
        let runner = ScriptedRunner(results: [])

        await #expect(throws: DeveloperToolCommandError.self) {
            try await LocalSnapshotReleaser(runner: runner, freeSpace: { nil }).release(bytes: 0)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test("bytes not yet freed count removed allocated size minus measured change, excluding Trash")
    func bytesNotYetFreed() {
        let result = DeveloperStorageCleanupResult(
            items: [
                DeveloperStorageCleanupResultItem(itemID: "a", name: "a", bytes: 0, status: .removed, message: "", allocatedBytes: 3_000),
                DeveloperStorageCleanupResultItem(itemID: "b", name: "b", bytes: 500, status: .removed, message: "", movedToTrash: true, allocatedBytes: 500),
                DeveloperStorageCleanupResultItem(itemID: "c", name: "c", bytes: 900, status: .skipped, message: "", allocatedBytes: 900)
            ],
            freeBytesBefore: 10_000,
            freeBytesAfter: 11_000
        )

        #expect(result.bytesNotYetFreed == 2_000)
        #expect(result.removedAllocatedBytes == 3_500)
        #expect(result.removedBytes == 500)
        #expect(result.unresolvedItems.map(\.itemID) == ["c"])
        #expect(result.bytesInTrash == 500)
        #expect(DeveloperStorageCleanupResult(items: result.items).bytesNotYetFreed == nil)
    }

    // MARK: Names and totals

    @Test("runtime identifiers become readable versions for device names")
    func formatsRuntimeNames() {
        #expect(DeveloperStorageAnalyzer.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.iOS-27-2") == "iOS 27.2")
        #expect(DeveloperStorageAnalyzer.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.watchOS-26-5") == "watchOS 26.5")
        #expect(DeveloperStorageAnalyzer.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.xrOS-3-0-1") == "xrOS 3.0.1")
    }

    @Test("device names include the runtime so the same model on two runtimes is distinguishable")
    func deviceNamesIncludeRuntime() async throws {
        let home = try TemporaryDirectory().url
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Developer"), withIntermediateDirectories: true)
        let devices = Data("""
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"udid":"A","name":"iPad (A16)","state":"Shutdown","isAvailable":true}],
          "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"B","name":"iPad (A16)","state":"Shutdown","isAvailable":true}]
        }}
        """.utf8)
        let runner = RoutingCommandRunner(routes: ["simctl list --json": devices])

        let inventory = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: runner, agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []).analyze()
        let names = Set(inventory.items.filter { $0.category == .simulatorDevices }.map(\.name))

        #expect(names == ["iPad (A16) · iOS 27.2", "iPad (A16) · iOS 26.5"])
    }

    @Test("eventually reclaimable space counts private size for device clones and allocated size otherwise")
    func eventuallyReclaimable() {
        let clone = deviceItem(category: .xctestDevices, udid: "CLONE-1").withMinimumReclaimableBytes(400)
        let derived = trashItem(category: .derivedData, url: URL(fileURLWithPath: "/tmp/dd"), decision: DeveloperStoragePolicy().decision(for: .derivedData))
            .withMinimumReclaimableBytes(0)

        #expect(clone.eventuallyReclaimableBytes == 400)
        #expect(derived.eventuallyReclaimableBytes == 1_024)
        #expect(DeveloperStorageInventory(items: [clone, derived], simulatorToolAvailable: true).eventuallyReclaimableBytes(for: .recommended) == 1_424)
    }

    // MARK: Claude sessions and AI app caches

    private func writeSessionRecord(home: URL, pid: Int32, sessionID: String) throws {
        let directory = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = try JSONSerialization.data(withJSONObject: ["pid": pid, "sessionId": sessionID, "status": "idle"])
        try record.write(to: directory.appendingPathComponent("\(pid).json"))
    }

    @Test("session registry reports only sessions whose process is alive, and nil when unreadable")
    func readsSessionRegistry() throws {
        let home = try TemporaryDirectory().url
        #expect(ClaudeSessionRegistry(homeDirectory: home).liveSessionIDs() == nil)
        try writeSessionRecord(home: home, pid: 100, sessionID: "AAAAAAAA-0000-0000-0000-000000000001")
        try writeSessionRecord(home: home, pid: 200, sessionID: "aaaaaaaa-0000-0000-0000-000000000002")

        let live = ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { $0 == 100 }).liveSessionIDs()

        #expect(live == ["aaaaaaaa-0000-0000-0000-000000000001"])
    }

    @Test("closed sessions become one recommended item; live and unnamed folders keep the build-only scan")
    func inventoriesClaudeSessions() async throws {
        let home = try TemporaryDirectory().url
        let temp = home.appendingPathComponent("agent-tmp")
        let project = temp.appendingPathComponent("-Users-me-PetroCheck")
        let closedID = "11111111-2222-3333-4444-555555555555"
        let liveID = "66666666-7777-8888-9999-000000000000"
        let closed = project.appendingPathComponent(closedID)
        let live = project.appendingPathComponent(liveID)
        let unnamed = project.appendingPathComponent("not-a-session")
        try FileManager.default.createDirectory(at: closed.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_100_000).write(to: closed.appendingPathComponent("images/shot.png"))
        for folder in [live, unnamed] {
            let build = folder.appendingPathComponent("scratchpad/dd")
            try FileManager.default.createDirectory(at: build.appendingPathComponent("Build"), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/p/App.xcodeproj"], format: .xml, options: 0)
            try plist.write(to: build.appendingPathComponent("info.plist"))
        }
        try writeSessionRecord(home: home, pid: 42, sessionID: liveID)
        let analyzer = DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            agentTemporaryRoot: temp,
            homebrewExecutables: [],
            sessionRegistry: ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { $0 == 42 }),
            now: { Date().addingTimeInterval(7_200) }
        )

        let items = try await analyzer.analyze().items.filter { $0.category == .aiGeneratedArtifacts }

        let session = try #require(items.first { $0.isClosedClaudeSession })
        #expect(session.url?.lastPathComponent == closedID)
        #expect(session.recommendation == .recommended)
        #expect(session.xcodeActivityRule == .independent)
        #expect(items.filter(\.isClosedClaudeSession).count == 1)
        #expect(items.filter { $0.name.hasPrefix("Claude build data:") }.count == 2)
    }

    @Test("a closed session written to in the last hour is review-only")
    func recentSessionIsReview() async throws {
        let home = try TemporaryDirectory().url
        let temp = home.appendingPathComponent("agent-tmp")
        let session = temp.appendingPathComponent("project/11111111-2222-3333-4444-555555555555/images")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_100_000).write(to: session.appendingPathComponent("shot.png"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)

        let items = try await DeveloperStorageAnalyzer(
            homeDirectory: home, commandRunner: RoutingCommandRunner(routes: [:]), agentTemporaryRoot: temp,
            homebrewExecutables: [], sessionRegistry: ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { _ in false })
        ).analyze().items

        #expect(items.first { $0.isClosedClaudeSession }?.recommendation == .review)
    }

    @Test("session cleanup rechecks the registry and open files before moving anything")
    func sessionCleanupRechecks() async throws {
        let home = try TemporaryDirectory().url
        let sessionID = "11111111-2222-3333-4444-555555555555"
        let folder = home.appendingPathComponent("tmp/project/\(sessionID)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decision = DeveloperStoragePolicy().closedClaudeSessionDecision()
        let item = DeveloperStorageItem(
            id: "path:\(folder.path)", category: .aiGeneratedArtifacts, name: "Claude session", detail: "",
            url: folder, bytes: 4_096, activity: decision.activity, recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism, consequence: decision.consequence,
            recommendation: decision.recommendation, recommendationReason: decision.reason,
            externalIdentifier: ClaudeSessionRegistry.itemIdentifierPrefix + sessionID
        )
        let quiet = OpenFileSnapshot(paths: ["/unrelated"])

        // Resumed since the scan.
        try writeSessionRecord(home: home, pid: 7, sessionID: sessionID)
        let resumed = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: true, snapshot: quiet), freeSpace: { nil },
            sessionRegistry: ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { _ in true })
        ).execute(items: [item])
        #expect(resumed.items.first?.status == .skipped)

        // Closed, but the open-file snapshot fails.
        let unknown = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: false, snapshot: nil), freeSpace: { nil },
            sessionRegistry: ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { _ in false })
        ).execute(items: [item])
        #expect(unknown.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: folder.path))

        // Closed, nothing open, Xcode running: removed.
        let removed = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: true, snapshot: quiet), freeSpace: { nil },
            sessionRegistry: ClaudeSessionRegistry(homeDirectory: home, isProcessAlive: { _ in false })
        ).execute(items: [item])
        #expect(removed.items.first?.status == .removed)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("Codex and Antigravity caches are recommended and skipped while files inside are open")
    func aiAppCaches() async throws {
        let home = try TemporaryDirectory().url
        let codex = home.appendingPathComponent("Library/Caches/com.openai.codex")
        let antigravity = home.appendingPathComponent("Library/Application Support/Antigravity/Cache")
        for folder in [codex, antigravity] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4_096).write(to: folder.appendingPathComponent("data"))
        }

        let items = try await DeveloperStorageAnalyzer(
            homeDirectory: home, commandRunner: RoutingCommandRunner(routes: [:]),
            agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []
        ).analyze().items.filter { $0.category == .aiCaches }
        #expect(Set(items.map(\.name)) == ["Codex App Cache", "Antigravity Cache"])
        #expect(items.allSatisfy { $0.recommendation == .recommended && $0.requiresOpenFileCheck })

        let codexItem = try #require(items.first { $0.name == "Codex App Cache" })
        let open = OpenFileSnapshot(paths: [codex.appendingPathComponent("data").resolvingSymlinksInPath().path])
        let result = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: false, snapshot: open), freeSpace: { nil }
        ).execute(items: [codexItem])
        #expect(result.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: codex.path))
    }

    // MARK: Symbolic links

    @Test("analyzer never lists a symbolic link, such as ~/.swiftpm/cache pointing at the SwiftPM cache")
    func skipsSymbolicLinks() async throws {
        let home = try TemporaryDirectory().url
        let target = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: target.appendingPathComponent("repo.bin"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".swiftpm"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".swiftpm/cache"), withDestinationURL: target)

        let inventory = try await DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: RoutingCommandRunner(routes: [:]),
            agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: []
        ).analyze()

        #expect(inventory.items.contains { $0.name == "SwiftPM Package Cache" })
        #expect(!inventory.items.contains { $0.name == "SwiftPM Binary Cache" })
    }

    @Test("cleanup refuses a symbolic link and leaves both the link and its target")
    func refusesSymbolicLinkCleanup() async throws {
        let root = try TemporaryDirectory().url
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = await DeveloperStorageCleanupExecutor(
            activityChecker: StubActivityChecker(isRunning: false),
            freeSpace: { nil }
        ).execute(items: [trashItem(category: .packageCaches, url: link, decision: DeveloperStoragePolicy().decision(for: .packageCaches))])

        #expect(result.items.first?.status == .skipped)
        #expect(result.items.first?.message.contains("symbolic link") == true)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(FileManager.default.fileExists(atPath: target.path))
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
            agentTemporaryRoot: home.appendingPathComponent("agent-tmp"), homebrewExecutables: [brew],
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
    var xcodebuildRunning = false

    func isXcodeRunning() async -> Bool { isRunning }
    func openFileSnapshot() async -> OpenFileSnapshot? { snapshot }
    func isXcodebuildRunning() async -> Bool { xcodebuildRunning }
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
