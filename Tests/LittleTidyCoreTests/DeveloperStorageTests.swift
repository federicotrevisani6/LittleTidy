import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Developer storage")
struct DeveloperStorageTests {
    @Test("simctl parser preserves devices, runtimes, availability, and paths")
    func parsesSimulatorInventory() throws {
        let data = Data(
            """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
                  {
                    "name": "iPhone 16 Pro",
                    "udid": "DEVICE-1",
                    "state": "Shutdown",
                    "isAvailable": true,
                    "dataPath": "/tmp/device-1"
                  },
                  {
                    "name": "Old iPhone",
                    "udid": "DEVICE-2",
                    "state": "Shutdown",
                    "availability": "(unavailable, runtime profile not found)"
                  }
                ]
              },
              "runtimes": [
                {
                  "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                  "name": "iOS 18.4",
                  "version": "18.4",
                  "isAvailable": true,
                  "bundlePath": "/tmp/iOS 18.4.simruntime"
                }
              ]
            }
            """.utf8
        )

        let inventory = try SimulatorInventoryParser().parse(data)

        #expect(inventory.devices.count == 2)
        #expect(inventory.devices.first { $0.udid == "DEVICE-1" }?.dataPath == "/tmp/device-1")
        #expect(inventory.devices.first { $0.udid == "DEVICE-2" }?.isAvailable == false)
        #expect(inventory.runtimes == [
            SimulatorRuntimeRecord(
                identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                name: "iOS 18.4",
                version: "18.4",
                isAvailable: true,
                bundlePath: "/tmp/iOS 18.4.simruntime"
            )
        ])
    }

    @Test("runtime disk image parser uses exact installed size and deletion identifier")
    func parsesRuntimeDiskImages() throws {
        let data = Data(
            """
            {
              "RUNTIME-IMAGE-1": {
                "identifier": "RUNTIME-IMAGE-1",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                "version": "18.4",
                "build": "22E240",
                "sizeBytes": 8123456789,
                "lastUsedAt": "2026-07-10T13:26:36Z",
                "deletable": true,
                "state": "Ready",
                "runtimeBundlePath": "/tmp/iOS 18.4.simruntime"
              }
            }
            """.utf8
        )

        let images = try SimulatorInventoryParser().parseRuntimeDiskImages(data)

        #expect(images.count == 1)
        #expect(images[0].identifier == "RUNTIME-IMAGE-1")
        #expect(images[0].sizeBytes == 8_123_456_789)
        #expect(images[0].isDeletable)
        #expect(images[0].lastUsedAt != nil)
    }

    @Test("policy protects active devices and recommends unavailable devices")
    func protectsActiveDevices() {
        let policy = DeveloperStoragePolicy()
        let active = policy.decision(for: .simulatorDevices, isAvailable: true, isActive: true)
        let unavailable = policy.decision(for: .simulatorDevices, isAvailable: false, isActive: false)
        let archive = policy.decision(for: .archives)

        #expect(active.recommendation == .protected)
        #expect(active.activity == .active)
        #expect(unavailable.recommendation == .recommended)
        #expect(unavailable.mechanism == .simctl)
        #expect(archive.recommendation == .protected)
    }

    @Test("analyzer inventories developer categories without flattening them into caches")
    func inventoriesDeveloperStorage() async throws {
        let home = try TemporaryDirectory().url
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let deviceSupport = home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/18.4", isDirectory: true)
        let archive = home.appendingPathComponent("Library/Developer/Xcode/Archives/2026-07-01/App 01-07-26.xcarchive", isDirectory: true)
        let xctestDevices = home.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
        let simulatorDevice = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/DEVICE-1/data", isDirectory: true)
        let runtime = home.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime", isDirectory: true)
        for directory in [derivedData, deviceSupport, archive, xctestDevices, simulatorDevice, runtime] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4_096).write(to: directory.appendingPathComponent("payload.bin"))
        }

        let simctlJSON = Data(
            """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
                  {
                    "name": "iPhone 16 Pro",
                    "udid": "DEVICE-1",
                    "state": "Booted",
                    "isAvailable": true,
                    "dataPath": "\(simulatorDevice.path)"
                  }
                ]
              },
              "runtimes": [
                {
                  "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                  "name": "iOS 18.4",
                  "version": "18.4",
                  "isAvailable": true,
                  "bundlePath": "\(runtime.path)"
                }
              ]
            }
            """.utf8
        )
        let analyzer = DeveloperStorageAnalyzer(
            homeDirectory: home,
            commandRunner: FixtureCommandRunner(output: simctlJSON)
        )

        let inventory = try await analyzer.analyze()

        #expect(inventory.items.contains { $0.category == .derivedData && $0.recommendation == .recommended })
        #expect(inventory.items.contains { $0.category == .deviceSupport })
        #expect(inventory.items.contains { $0.category == .archives && $0.recommendation == .protected })
        #expect(inventory.items.contains { $0.category == .xctestDevices && $0.recommendation == .unclassified })
        #expect(inventory.items.contains { $0.category == .simulatorDevices && $0.recommendation == .protected })
        #expect(inventory.items.contains { $0.category == .simulatorRuntimes && $0.recommendation == .review })
        #expect(inventory.bytes(for: .recommended) > 0)
        #expect(inventory.simulatorToolAvailable)
    }

    @Test("cleanup moves recommended rebuildable data to Trash")
    func trashesRecommendedData() async throws {
        let root = try TemporaryDirectory().url
        let derivedData = root.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: derivedData.appendingPathComponent("build.o"))
        let decision = DeveloperStoragePolicy().decision(for: .derivedData)
        let item = makeItem(
            id: "derived",
            category: .derivedData,
            url: derivedData,
            decision: decision
        )

        let result = await DeveloperStorageCleanupExecutor().execute(items: [item])

        #expect(result.items.first?.status == .removed)
        #expect(!FileManager.default.fileExists(atPath: derivedData.path))
    }

    @Test("cleanup revalidates unavailable simulator before deleting with simctl")
    func revalidatesSimulatorState() async throws {
        let deviceJSON = Data(
            """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
                  {
                    "name": "Old iPhone",
                    "udid": "DEVICE-OLD",
                    "state": "Shutdown",
                    "isAvailable": false
                  }
                ]
              }
            }
            """.utf8
        )
        let runner = ScriptedCommandRunner(results: [
            DeveloperToolCommandResult(standardOutput: deviceJSON),
            DeveloperToolCommandResult(standardOutput: Data())
        ])
        let decision = DeveloperStoragePolicy().decision(for: .simulatorDevices, isAvailable: false)
        let item = DeveloperStorageItem(
            id: "simulator-device:DEVICE-OLD",
            category: .simulatorDevices,
            name: "Old iPhone",
            detail: "Unavailable",
            url: nil,
            bytes: 2_000,
            activity: decision.activity,
            recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism,
            consequence: decision.consequence,
            recommendation: decision.recommendation,
            recommendationReason: decision.reason,
            externalIdentifier: "DEVICE-OLD",
            isAvailable: false
        )

        let result = await DeveloperStorageCleanupExecutor(commandRunner: runner).execute(items: [item])
        let calls = await runner.calls

        #expect(result.items.first?.status == .removed)
        #expect(calls.count == 2)
        #expect(calls.last?.arguments == ["simctl", "delete", "DEVICE-OLD"])
    }

    @Test("runtime cleanup revalidates runtime and dependencies before supported deletion")
    func revalidatesRuntime() async throws {
        let runtimeJSON = Data(
            """
            {
              "RUNTIME-IMAGE-1": {
                "identifier": "RUNTIME-IMAGE-1",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                "version": "18.4",
                "build": "22E240",
                "sizeBytes": 8123456789,
                "deletable": true,
                "state": "Ready"
              }
            }
            """.utf8
        )
        let devicesJSON = Data("{\"devices\":{}}".utf8)
        let runner = ScriptedCommandRunner(results: [
            DeveloperToolCommandResult(standardOutput: runtimeJSON),
            DeveloperToolCommandResult(standardOutput: devicesJSON),
            DeveloperToolCommandResult(standardOutput: Data())
        ])
        let decision = DeveloperStoragePolicy().decision(for: .simulatorRuntimes)
        let item = DeveloperStorageItem(
            id: "simulator-runtime:RUNTIME-IMAGE-1",
            category: .simulatorRuntimes,
            name: "iOS 18.4",
            detail: "Version 18.4",
            url: nil,
            bytes: 8_123_456_789,
            activity: decision.activity,
            recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism,
            consequence: decision.consequence,
            recommendation: decision.recommendation,
            recommendationReason: decision.reason,
            externalIdentifier: "RUNTIME-IMAGE-1",
            isAvailable: true
        )

        let result = await DeveloperStorageCleanupExecutor(commandRunner: runner).execute(items: [item])
        let calls = await runner.calls

        #expect(result.items.first?.status == .removed)
        #expect(calls.last?.arguments == ["simctl", "runtime", "delete", "RUNTIME-IMAGE-1"])
    }

    private func makeItem(
        id: String,
        category: DeveloperStorageCategory,
        url: URL,
        decision: DeveloperStorageDecision
    ) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: id,
            category: category,
            name: url.lastPathComponent,
            detail: category.displayName,
            url: url,
            bytes: 1_024,
            activity: decision.activity,
            recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism,
            consequence: decision.consequence,
            recommendation: decision.recommendation,
            recommendationReason: decision.reason,
            isAvailable: true
        )
    }
}

private struct FixtureCommandRunner: DeveloperToolCommandRunning {
    let output: Data

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        DeveloperToolCommandResult(standardOutput: output)
    }
}

private actor ScriptedCommandRunner: DeveloperToolCommandRunning {
    struct Call: Sendable {
        let executable: URL
        let arguments: [String]
    }

    private var results: [DeveloperToolCommandResult]
    private(set) var calls: [Call] = []

    init(results: [DeveloperToolCommandResult]) {
        self.results = results
    }

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            throw DeveloperToolCommandError.unavailable(executable.path)
        }
        return results.removeFirst()
    }
}
