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
    /// True when the item went to the Trash, where it still occupies space.
    public let movedToTrash: Bool
    /// The item's allocated size, which can exceed `bytes` when part of it is
    /// shared with clones or held by a local snapshot.
    public let allocatedBytes: Int64

    public init(
        itemID: String,
        name: String,
        bytes: Int64,
        status: DeveloperStorageCleanupStatus,
        message: String,
        movedToTrash: Bool = false,
        allocatedBytes: Int64? = nil
    ) {
        self.itemID = itemID
        self.name = name
        self.bytes = bytes
        self.status = status
        self.message = message
        self.movedToTrash = movedToTrash
        self.allocatedBytes = allocatedBytes ?? bytes
    }
}

public struct DeveloperStorageCleanupResult: Codable, Equatable, Sendable {
    public let items: [DeveloperStorageCleanupResultItem]
    /// Volume free space measured immediately before and after the batch.
    public let freeBytesBefore: Int64?
    public let freeBytesAfter: Int64?

    public init(
        items: [DeveloperStorageCleanupResultItem],
        freeBytesBefore: Int64? = nil,
        freeBytesAfter: Int64? = nil
    ) {
        self.items = items
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
    }

    /// Space guaranteed to be freed by the removed items (lower bound).
    public var removedBytes: Int64 {
        items.filter { $0.status == .removed }.reduce(0) { $0 + $1.bytes }
    }

    /// Allocated size of everything removed, including space that clones or a
    /// local snapshot still hold.
    public var removedAllocatedBytes: Int64 {
        items.filter { $0.status == .removed }.reduce(0) { $0 + $1.allocatedBytes }
    }

    /// Items that were not removed, with the executor's reason for each.
    public var unresolvedItems: [DeveloperStorageCleanupResultItem] {
        items.filter { $0.status != .removed }
    }

    /// Bytes now in the Trash. They are freed only when the Trash is emptied.
    public var bytesInTrash: Int64 {
        items.filter { $0.status == .removed && $0.movedToTrash }.reduce(0) { $0 + $1.bytes }
    }

    /// The measured change in free space. Other apps write to the same volume,
    /// so this is an observation, not an exact accounting of this cleanup.
    public var measuredFreedBytes: Int64? {
        guard let freeBytesBefore, let freeBytesAfter else { return nil }
        return freeBytesAfter - freeBytesBefore
    }

    /// Removed data whose space did not come back. Trashed items still exist,
    /// so they are excluded: they occupy space until the Trash is emptied.
    public var bytesNotYetFreed: Int64? {
        guard let measuredFreedBytes else { return nil }
        let removed = items
            .filter { $0.status == .removed && !$0.movedToTrash }
            .reduce(Int64(0)) { $0 + $1.allocatedBytes }
        return max(0, removed - max(0, measuredFreedBytes))
    }
}

public actor DeveloperStorageCleanupExecutor {
    private let fileManager: FileManager
    private let commandRunner: any DeveloperToolCommandRunning
    private let activityChecker: any DeveloperToolActivityChecking
    private let homebrewRunner: any DeveloperToolCommandRunning
    private let freeSpace: @Sendable () -> Int64?

    public init(
        fileManager: FileManager = .default,
        commandRunner: any DeveloperToolCommandRunning = DeveloperToolCommandClient(),
        activityChecker: (any DeveloperToolActivityChecking)? = nil,
        homebrewRunner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 900, environment: HomebrewCleanup.environment),
        freeSpace: @escaping @Sendable () -> Int64? = DeveloperStorageCleanupExecutor.homeVolumeFreeBytes
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.activityChecker = activityChecker ?? DeveloperToolActivityChecker()
        self.homebrewRunner = homebrewRunner
        self.freeSpace = freeSpace
    }

    @Sendable public static func homeVolumeFreeBytes() -> Int64? {
        let values = try? FileManager.default.homeDirectoryForCurrentUser
            .resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    public func execute(items: [DeveloperStorageItem], deletionMode: DeletionMode = .moveToTrash) async -> DeveloperStorageCleanupResult {
        var results: [DeveloperStorageCleanupResultItem] = []
        let freeBytesBefore = freeSpace()

        for item in items {
            if Task.isCancelled { break }
            // Rechecked before every item: Xcode can open, or a project can
            // start building, while an earlier item is being removed.
            if let blockingReason = await xcodeBlockingReason(for: item) {
                results.append(result(item, status: .skipped, message: blockingReason))
                continue
            }
            switch item.cleanupMechanism {
            case .trash:
                results.append(moveToTrash(item, deletionMode: deletionMode))
            case .simctl:
                results.append(await deleteSimulatorDevice(item))
            case .xcodeManaged:
                results.append(await deleteSimulatorRuntime(item))
            case .homebrewCleanup:
                results.append(await runHomebrewCleanup(item))
            case .manual, .unsupported:
                results.append(result(
                    item,
                    status: .skipped,
                    message: "No verified automatic cleanup mechanism is available."
                ))
            }
        }

        return DeveloperStorageCleanupResult(
            items: results,
            freeBytesBefore: freeBytesBefore,
            freeBytesAfter: freeSpace()
        )
    }

    /// Fail-closed Xcode guard. Items Xcode owns are blocked while it runs,
    /// except per-project build data and Simulator devices that no process
    /// has open. If the open-file snapshot fails, the item stays blocked.
    private func xcodeBlockingReason(for item: DeveloperStorageItem) async -> String? {
        switch item.xcodeActivityRule {
        case .independent:
            return nil
        case .requiresXcodeQuit:
            guard await activityChecker.isXcodeRunning() else { return nil }
            return "Quit Xcode before cleaning this item. No data was removed for this item."
        case .openFileCheck:
            guard await activityChecker.isXcodeRunning() else { return nil }
            guard let snapshot = await activityChecker.openFileSnapshot() else {
                return "Xcode is open and LittleTidy could not verify that this item is unused. Quit Xcode to clean it. No data was removed for this item."
            }
            if let url = item.url, snapshot.containsPath(within: url) {
                return "In use by Xcode, a build, or a running Simulator. Close the project or quit Xcode to clean it. No data was removed for this item."
            }
            return nil
        }
    }

    private func moveToTrash(_ item: DeveloperStorageItem, deletionMode: DeletionMode = .moveToTrash) -> DeveloperStorageCleanupResultItem {
        guard item.cleanupMechanism == .trash,
              item.activity != .active,
              item.recommendation != .unclassified else {
            return result(item, status: .skipped, message: "This item is active or has no verified cleanup path.")
        }
        guard let url = item.url else {
            return result(item, status: .failed, message: "The item has no filesystem location.")
        }
        // attributesOfItem does not follow links, unlike fileExists.
        if (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            return result(item, status: .skipped, message: "The item is a symbolic link. LittleTidy never removes links.")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return result(item, status: .skipped, message: "The item no longer exists.")
        }

        do {
            if deletionMode == .permanentDelete {
                try fileManager.removeItem(at: url)
            } else {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            }
        } catch {
            return result(item, status: .failed, message: remainingDataMessage(for: url, error: error))
        }
        guard !fileManager.fileExists(atPath: url.path) else {
            return result(item, status: .failed, message: "The item is still present after cleanup. Another process may have recreated it.")
        }
        return deletionMode == .permanentDelete
            ? result(item, status: .removed, message: "Permanently deleted.")
            : result(item, status: .removed, message: "Moved to Trash. Empty the Trash to free this space.", movedToTrash: true)
    }

    /// A failed permanent delete can leave part of a tree behind, for example
    /// when a running build writes into it. Report what remains.
    private func remainingDataMessage(for url: URL, error: Error) -> String {
        guard fileManager.fileExists(atPath: url.path) else { return error.localizedDescription }
        return "\(error.localizedDescription) Part of the item may remain at \(url.path)."
    }

    /// XCTest clones live in simctl's dedicated "testing" device set.
    private func simctlPrefix(for item: DeveloperStorageItem) -> [String] {
        item.category == .xctestDevices ? ["simctl", "--set", "testing"] : ["simctl"]
    }

    private func deleteSimulatorDevice(_ item: DeveloperStorageItem) async -> DeveloperStorageCleanupResultItem {
        guard item.category == .simulatorDevices || item.category == .xctestDevices,
              item.cleanupMechanism == .simctl,
              item.activity != .active,
              (item.recommendation == .recommended || item.recommendation == .review),
              let udid = item.externalIdentifier else {
            return result(item, status: .skipped, message: "Only explicitly selected, inactive simulator devices can be removed.")
        }
        if item.category == .xctestDevices, await activityChecker.isXcodebuildRunning() {
            return result(item, status: .skipped, message: "xcodebuild is running and may be using this test clone. Try again after the run finishes.")
        }

        let prefix = simctlPrefix(for: item)
        do {
            let current = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: prefix + ["list", "devices", "--json"]
            )
            let inventory = try SimulatorInventoryParser().parse(current.standardOutput)
            guard let currentDevice = inventory.devices.first(where: { $0.udid == udid }) else {
                return result(item, status: .skipped, message: "The simulator device no longer exists.")
            }
            guard currentDevice.state.localizedCaseInsensitiveCompare("Booted") != .orderedSame else {
                return result(item, status: .skipped, message: "The simulator state changed and is no longer safe to remove.")
            }
            // Xcode can boot any clone of the testing set during a run, so a
            // shutdown clone is only removable when the whole set is idle.
            if item.category == .xctestDevices, inventory.devices.hasActiveTestSession {
                return result(item, status: .skipped, message: "An Xcode test session is using clones from this set. Try again after the run finishes.")
            }

            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: prefix + ["delete", udid]
            )
            if let url = item.url, fileManager.fileExists(atPath: url.path) {
                return result(item, status: .failed, message: "simctl reported success, but the device folder is still present.")
            }
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

    private func runHomebrewCleanup(_ item: DeveloperStorageItem) async -> DeveloperStorageCleanupResultItem {
        guard item.cleanupMechanism == .homebrewCleanup,
              let path = item.externalIdentifier,
              HomebrewCleanup.isKnownExecutable(path),
              fileManager.isExecutableFile(atPath: path) else {
            return result(item, status: .skipped, message: "Only a standard Homebrew installation can be cleaned.")
        }
        do {
            let output = try await homebrewRunner.run(
                executable: URL(fileURLWithPath: path),
                arguments: HomebrewCleanup.cleanupArguments
            )
            // Homebrew reports what it actually removed, which can differ
            // from the scan estimate if packages changed in between.
            let freed = HomebrewCleanup.parseReclaimedBytes(output.standardOutput) ?? 0
            return DeveloperStorageCleanupResultItem(
                itemID: item.id,
                name: item.name,
                bytes: freed,
                status: .removed,
                message: "Removed with brew cleanup. Reinstall any version with brew if you need it."
            )
        } catch {
            return result(item, status: .failed, message: error.localizedDescription)
        }
    }

    private func result(
        _ item: DeveloperStorageItem,
        status: DeveloperStorageCleanupStatus,
        message: String,
        movedToTrash: Bool = false
    ) -> DeveloperStorageCleanupResultItem {
        DeveloperStorageCleanupResultItem(
            itemID: item.id,
            name: item.name,
            bytes: status == .removed ? item.guaranteedReclaimableBytes : item.bytes,
            status: status,
            message: message,
            movedToTrash: movedToTrash,
            allocatedBytes: item.bytes
        )
    }
}
