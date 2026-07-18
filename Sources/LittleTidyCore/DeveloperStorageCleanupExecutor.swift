import Foundation

public enum DeveloperStorageCleanupStatus: String, Codable, Sendable {
    case removed
    case skipped
    case failed
}

public struct DeveloperStorageCleanupResultItem: Codable, Equatable, Sendable {
    public let itemID: String
    public let name: String
    public let bytes: Int64
    public let status: DeveloperStorageCleanupStatus
    public let message: String

    public init(itemID: String, name: String, bytes: Int64, status: DeveloperStorageCleanupStatus, message: String) {
        self.itemID = itemID
        self.name = name
        self.bytes = bytes
        self.status = status
        self.message = message
    }
}

public struct DeveloperStorageCleanupResult: Codable, Equatable, Sendable {
    public let items: [DeveloperStorageCleanupResultItem]

    public init(items: [DeveloperStorageCleanupResultItem]) {
        self.items = items
    }

    public var removedBytes: Int64 {
        items.filter { $0.status == .removed }.reduce(0) { $0 + $1.bytes }
    }
}

public actor DeveloperStorageCleanupExecutor {
    private let fileManager: FileManager
    private let commandRunner: any DeveloperToolCommandRunning
    private let activityChecker: any DeveloperToolActivityChecking

    public init(
        fileManager: FileManager = .default,
        commandRunner: any DeveloperToolCommandRunning = DeveloperToolCommandClient(),
        activityChecker: (any DeveloperToolActivityChecking)? = nil
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.activityChecker = activityChecker ?? DeveloperToolActivityChecker()
    }

    public func execute(items: [DeveloperStorageItem]) async -> DeveloperStorageCleanupResult {
        var results: [DeveloperStorageCleanupResultItem] = []

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            if await activityChecker.isXcodeRunning() {
                results.append(contentsOf: items[index...].map { pendingItem in
                    result(
                        pendingItem,
                        status: .skipped,
                        message: "Quit Xcode before cleaning developer storage. No data was removed for this item."
                    )
                })
                break
            }
            switch item.cleanupMechanism {
            case .trash:
                results.append(moveToTrash(item))
            case .simctl:
                results.append(await deleteSimulatorDevice(item))
            case .xcodeManaged:
                results.append(await deleteSimulatorRuntime(item))
            case .manual, .unsupported:
                results.append(result(
                    item,
                    status: .skipped,
                    message: "No verified automatic cleanup mechanism is available."
                ))
            }
        }

        return DeveloperStorageCleanupResult(items: results)
    }

    private func moveToTrash(_ item: DeveloperStorageItem) -> DeveloperStorageCleanupResultItem {
        guard item.cleanupMechanism == .trash,
              item.activity != .active,
              item.recommendation != .unclassified else {
            return result(item, status: .skipped, message: "This item is active or has no verified Trash cleanup path.")
        }
        guard let url = item.url else {
            return result(item, status: .failed, message: "The item has no filesystem location.")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return result(item, status: .skipped, message: "The item no longer exists.")
        }

        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            return result(item, status: .removed, message: "Moved to Trash.")
        } catch {
            return result(item, status: .failed, message: error.localizedDescription)
        }
    }

    private func deleteSimulatorDevice(_ item: DeveloperStorageItem) async -> DeveloperStorageCleanupResultItem {
        guard item.category == .simulatorDevices,
              item.cleanupMechanism == .simctl,
              item.activity != .active,
              (item.recommendation == .recommended || item.recommendation == .review),
              let udid = item.externalIdentifier else {
            return result(item, status: .skipped, message: "Only explicitly selected, inactive simulator devices can be removed.")
        }

        do {
            let current = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "--json"]
            )
            let inventory = try SimulatorInventoryParser().parse(current.standardOutput)
            guard let currentDevice = inventory.devices.first(where: { $0.udid == udid }) else {
                return result(item, status: .skipped, message: "The simulator device no longer exists.")
            }
            guard currentDevice.state.localizedCaseInsensitiveCompare("Booted") != .orderedSame else {
                return result(item, status: .skipped, message: "The simulator state changed and is no longer safe to remove.")
            }

            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "delete", udid]
            )
            return result(item, status: .removed, message: "Removed with simctl. This operation is not undoable.")
        } catch {
            return result(item, status: .failed, message: error.localizedDescription)
        }
    }

    private func deleteSimulatorRuntime(_ item: DeveloperStorageItem) async -> DeveloperStorageCleanupResultItem {
        guard item.category == .simulatorRuntimes,
              item.recommendation == .review,
              let identifier = item.externalIdentifier else {
            return result(item, status: .skipped, message: "Only explicitly reviewed Simulator runtimes can be removed.")
        }

        do {
            let runtimeResult = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "runtime", "list", "--json"]
            )
            let diskImages = try SimulatorInventoryParser().parseRuntimeDiskImages(runtimeResult.standardOutput)
            guard let diskImage = diskImages.first(where: { $0.identifier == identifier }), diskImage.isDeletable else {
                return result(item, status: .skipped, message: "The runtime is no longer present or is not deletable.")
            }

            let devicesResult = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "--json"]
            )
            let devices = try SimulatorInventoryParser().parse(devicesResult.standardOutput).devices
            let dependentDevices = devices.filter { $0.runtimeIdentifier == diskImage.runtimeIdentifier }
            guard !dependentDevices.contains(where: { $0.state.localizedCaseInsensitiveCompare("Booted") == .orderedSame }) else {
                return result(item, status: .skipped, message: "A simulator using this runtime is currently booted.")
            }

            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "runtime", "delete", identifier]
            )
            let suffix = dependentDevices.isEmpty
                ? ""
                : " \(dependentDevices.count) shutdown simulator devices will become unavailable until the runtime is reinstalled."
            return result(item, status: .removed, message: "Removed with simctl. Reinstallation requires a download.\(suffix)")
        } catch {
            return result(item, status: .failed, message: error.localizedDescription)
        }
    }

    private func result(
        _ item: DeveloperStorageItem,
        status: DeveloperStorageCleanupStatus,
        message: String
    ) -> DeveloperStorageCleanupResultItem {
        DeveloperStorageCleanupResultItem(
            itemID: item.id,
            name: item.name,
            bytes: item.bytes,
            status: status,
            message: message
        )
    }
}
