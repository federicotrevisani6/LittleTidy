import Foundation

public actor DeveloperStorageAnalyzer {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let commandRunner: any DeveloperToolCommandRunning
    private let policy: DeveloperStoragePolicy

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        commandRunner: any DeveloperToolCommandRunning = DeveloperToolCommandClient(),
        policy: DeveloperStoragePolicy = DeveloperStoragePolicy()
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.commandRunner = commandRunner
        self.policy = policy
    }

    public func analyze() async throws -> DeveloperStorageInventory {
        var items: [DeveloperStorageItem] = []
        var issues: [DeveloperStorageAccessIssue] = []

        let developerRoot = homeDirectory.appendingPathComponent("Library/Developer", isDirectory: true)
        let xcodeRoot = developerRoot.appendingPathComponent("Xcode", isDirectory: true)

        appendDirectory(
            xcodeRoot.appendingPathComponent("DerivedData", isDirectory: true),
            category: .derivedData,
            name: "Xcode Derived Data",
            detail: "Build products, indexes, and intermediates",
            items: &items,
            issues: &issues
        )
        appendChildren(
            of: xcodeRoot.appendingPathComponent("iOS DeviceSupport", isDirectory: true),
            category: .deviceSupport,
            items: &items,
            issues: &issues
        )
        appendArchiveChildren(
            of: xcodeRoot.appendingPathComponent("Archives", isDirectory: true),
            items: &items,
            issues: &issues
        )
        appendDirectory(
            developerRoot.appendingPathComponent("XCTestDevices", isDirectory: true),
            category: .xctestDevices,
            name: "XCTest Devices",
            detail: "Test device environments and data",
            items: &items,
            issues: &issues
        )

        let simulatorResult = await simulatorInventory()
        items.append(contentsOf: simulatorResult.items)
        issues.append(contentsOf: simulatorResult.issues)

        appendCoreSimulatorRemainder(
            developerRoot.appendingPathComponent("CoreSimulator", isDirectory: true),
            currentItems: items,
            items: &items,
            issues: &issues
        )
        appendUnknownChildren(
            of: xcodeRoot,
            excludingNames: ["DerivedData", "iOS DeviceSupport", "Archives"],
            items: &items,
            issues: &issues
        )
        appendUnknownChildren(
            of: developerRoot,
            excludingNames: ["Xcode", "CoreSimulator", "XCTestDevices"],
            items: &items,
            issues: &issues
        )

        return DeveloperStorageInventory(
            items: items.sorted { lhs, rhs in
                lhs.bytes == rhs.bytes
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.bytes > rhs.bytes
            },
            accessIssues: issues,
            simulatorToolAvailable: simulatorResult.toolAvailable
        )
    }

    private func simulatorInventory() async -> (items: [DeveloperStorageItem], issues: [DeveloperStorageAccessIssue], toolAvailable: Bool) {
        do {
            let result = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "--json"]
            )
            let inventory = try SimulatorInventoryParser().parse(result.standardOutput)
            let runtimeDiskImages: [SimulatorRuntimeDiskImageRecord]
            if let runtimeResult = try? await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "runtime", "list", "--json"]
            ) {
                runtimeDiskImages = (try? SimulatorInventoryParser().parseRuntimeDiskImages(runtimeResult.standardOutput)) ?? []
            } else {
                runtimeDiskImages = []
            }
            var items: [DeveloperStorageItem] = []
            let simulatorDeviceURLs = inventory.devices.compactMap { $0.dataPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }
            let measuredBytes = allocatedBytesUsingDU(at: simulatorDeviceURLs)

            for device in inventory.devices {
                try? Task.checkCancellation()
                let isActive = device.state.localizedCaseInsensitiveCompare("Booted") == .orderedSame
                let decision = policy.decision(
                    for: .simulatorDevices,
                    isAvailable: device.isAvailable,
                    isActive: isActive
                )
                let url = device.dataPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                items.append(makeItem(
                    id: "simulator-device:\(device.udid)",
                    category: .simulatorDevices,
                    name: device.name,
                    detail: "\(runtimeDisplayName(device.runtimeIdentifier)) · \(device.state)",
                    url: url,
                    externalIdentifier: device.udid,
                    isAvailable: device.isAvailable,
                    decision: decision,
                    premeasuredBytes: url.flatMap { measuredBytes[$0.standardizedFileURL.path] }
                ))
            }

            for runtime in inventory.runtimes {
                try? Task.checkCancellation()
                let decision = policy.decision(for: .simulatorRuntimes, isAvailable: runtime.isAvailable)
                let diskImage = runtimeDiskImages.first { $0.runtimeIdentifier == runtime.identifier }
                let url = (diskImage?.runtimeBundlePath ?? runtime.bundlePath).map { URL(fileURLWithPath: $0, isDirectory: true) }
                let lastUsedDetail = diskImage?.lastUsedAt.map { " · Last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                items.append(makeItem(
                    id: "simulator-runtime:\(diskImage?.identifier ?? runtime.identifier)",
                    category: .simulatorRuntimes,
                    name: runtime.name,
                    detail: "Version \(runtime.version)\(lastUsedDetail)",
                    url: url,
                    externalIdentifier: diskImage?.identifier ?? runtime.identifier,
                    isAvailable: runtime.isAvailable,
                    decision: decision,
                    premeasuredBytes: diskImage?.sizeBytes ?? url.flatMap(runtimeVolumeUsedBytes)
                ))
            }
            return (items, [], true)
        } catch {
            return (
                [],
                [DeveloperStorageAccessIssue(path: "/usr/bin/xcrun simctl", message: error.localizedDescription)],
                false
            )
        }
    }

    private func appendDirectory(
        _ url: URL,
        category: DeveloperStorageCategory,
        name: String,
        detail: String,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let decision = policy.decision(for: category)
        items.append(makeItem(
            id: "path:\(url.standardizedFileURL.path)",
            category: category,
            name: name,
            detail: detail,
            url: url,
            externalIdentifier: nil,
            isAvailable: true,
            decision: decision,
            issues: &issues
        ))
    }

    private func appendChildren(
        of root: URL,
        category: DeveloperStorageCategory,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        do {
            for child in try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                try Task.checkCancellation()
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let decision = policy.decision(for: category)
                items.append(makeItem(
                    id: "path:\(child.standardizedFileURL.path)",
                    category: category,
                    name: child.lastPathComponent,
                    detail: root.lastPathComponent,
                    url: child,
                    externalIdentifier: nil,
                    isAvailable: true,
                    decision: decision,
                    issues: &issues
                ))
            }
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: root.path, message: error.localizedDescription))
        }
    }

    private func appendArchiveChildren(
        of root: URL,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        do {
            let dateFolders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            for dateFolder in dateFolders {
                let archives = (try? fileManager.contentsOfDirectory(at: dateFolder, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
                for archive in archives where archive.pathExtension.lowercased() == "xcarchive" {
                    try Task.checkCancellation()
                    let decision = policy.decision(for: .archives)
                    items.append(makeItem(
                        id: "path:\(archive.standardizedFileURL.path)",
                        category: .archives,
                        name: archive.deletingPathExtension().lastPathComponent,
                        detail: "Xcode archive · \(dateFolder.lastPathComponent)",
                        url: archive,
                        externalIdentifier: nil,
                        isAvailable: true,
                        decision: decision,
                        issues: &issues
                    ))
                }
            }
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: root.path, message: error.localizedDescription))
        }
    }

    private func appendCoreSimulatorRemainder(
        _ root: URL,
        currentItems: [DeveloperStorageItem],
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        let rootSize = allocatedBytesUsingDU(at: root) ?? 0
        let deviceBytes = currentItems
            .filter { $0.category == .simulatorDevices }
            .filter { item in item.url?.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") == true }
            .reduce(Int64(0)) { $0 + $1.bytes }
        let remainder = max(0, rootSize - deviceBytes)
        guard remainder >= 1_000_000 else { return }
        let decision = policy.decision(for: .otherDeveloperData)
        items.append(DeveloperStorageItem(
            id: "core-simulator-remainder",
            category: .otherDeveloperData,
            name: "CoreSimulator Support Data",
            detail: "Logs, caches, images, and metadata not owned by an individual device",
            url: root,
            bytes: remainder,
            activity: decision.activity,
            recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism,
            consequence: decision.consequence,
            recommendation: decision.recommendation,
            recommendationReason: decision.reason,
            isAvailable: true
        ))
    }

    private func appendUnknownChildren(
        of root: URL,
        excludingNames: Set<String>,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        do {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children where !excludingNames.contains(child.lastPathComponent) {
                try Task.checkCancellation()
                let decision = policy.decision(for: .otherDeveloperData)
                if child.lastPathComponent == "CoreDevice" {
                    items.append(DeveloperStorageItem(
                        id: "path:\(child.standardizedFileURL.path)",
                        category: .otherDeveloperData,
                        name: "CoreDevice Mounted Filesystems",
                        detail: "Mounted device filesystems are protected and excluded from recursive size scans",
                        url: child,
                        bytes: 0,
                        activity: .active,
                        recoverability: .unknown,
                        cleanupMechanism: .unsupported,
                        consequence: .dataLossRisk,
                        recommendation: .protected,
                        recommendationReason: "This location exposes mounted device filesystems and must not be traversed or cleaned as ordinary files.",
                        isAvailable: true
                    ))
                    continue
                }
                let item = makeItem(
                    id: "path:\(child.standardizedFileURL.path)",
                    category: .otherDeveloperData,
                    name: child.lastPathComponent,
                    detail: "Additional developer storage",
                    url: child,
                    externalIdentifier: nil,
                    isAvailable: true,
                    decision: decision,
                    issues: &issues
                )
                if item.bytes >= 1_000_000 {
                    items.append(item)
                }
            }
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: root.path, message: error.localizedDescription))
        }
    }

    private func makeItem(
        id: String,
        category: DeveloperStorageCategory,
        name: String,
        detail: String,
        url: URL?,
        externalIdentifier: String?,
        isAvailable: Bool,
        decision: DeveloperStorageDecision,
        premeasuredBytes: Int64? = nil,
        issues: inout [DeveloperStorageAccessIssue]
    ) -> DeveloperStorageItem {
        let measurement: (bytes: Int64, createdAt: Date?, modifiedAt: Date?)
        if let premeasuredBytes {
            let dates = url.flatMap { try? $0.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) }
            measurement = (premeasuredBytes, dates?.creationDate, dates?.contentModificationDate)
        } else {
            measurement = measure(url, issues: &issues)
        }
        return DeveloperStorageItem(
            id: id,
            category: category,
            name: name,
            detail: detail,
            url: url,
            bytes: measurement.bytes,
            createdAt: measurement.createdAt,
            modifiedAt: measurement.modifiedAt,
            activity: decision.activity,
            recoverability: decision.recoverability,
            cleanupMechanism: decision.mechanism,
            consequence: decision.consequence,
            recommendation: decision.recommendation,
            recommendationReason: decision.reason,
            externalIdentifier: externalIdentifier,
            isAvailable: isAvailable
        )
    }

    private func makeItem(
        id: String,
        category: DeveloperStorageCategory,
        name: String,
        detail: String,
        url: URL?,
        externalIdentifier: String?,
        isAvailable: Bool,
        decision: DeveloperStorageDecision,
        premeasuredBytes: Int64? = nil
    ) -> DeveloperStorageItem {
        var ignoredIssues: [DeveloperStorageAccessIssue] = []
        return makeItem(
            id: id,
            category: category,
            name: name,
            detail: detail,
            url: url,
            externalIdentifier: externalIdentifier,
            isAvailable: isAvailable,
            decision: decision,
            premeasuredBytes: premeasuredBytes,
            issues: &ignoredIssues
        )
    }

    private func measure(_ url: URL?, issues: inout [DeveloperStorageAccessIssue]) -> (bytes: Int64, createdAt: Date?, modifiedAt: Date?) {
        guard let url else { return (0, nil, nil) }
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        guard fileManager.fileExists(atPath: url.path) else {
            return (0, dates?.creationDate, dates?.contentModificationDate)
        }
        if let bytes = allocatedBytesUsingDU(at: url) {
            return (bytes, dates?.creationDate, dates?.contentModificationDate)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else {
            issues.append(DeveloperStorageAccessIssue(path: url.path, message: "Unable to enumerate directory"))
            return (0, dates?.creationDate, dates?.contentModificationDate)
        }

        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return (bytes, dates?.creationDate, dates?.contentModificationDate)
    }

    /// `du` uses the same allocated-block accounting users see in storage tools
    /// and is substantially faster than materializing every URL in Swift for
    /// multi-gigabyte Simulator device trees. It is invoked directly, never
    /// through a shell, and falls back to FileManager traversal on failure.
    private func allocatedBytesUsingDU(at url: URL) -> Int64? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let firstField = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
                  let kibibytes = Int64(firstField) else {
                return nil
            }
            return kibibytes * 1_024
        } catch {
            return nil
        }
    }

    private func allocatedBytesUsingDU(at urls: [URL]) -> [String: Int64] {
        let uniqueURLs = Dictionary(grouping: urls, by: { $0.standardizedFileURL.path }).compactMap(\.value.first)
        guard !uniqueURLs.isEmpty else { return [:] }

        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk"] + uniqueURLs.map(\.path)
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [:] }

            var sizes: [String: Int64] = [:]
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let fields = line.split(separator: "\t", maxSplits: 1)
                guard fields.count == 2, let kibibytes = Int64(fields[0]) else { continue }
                sizes[URL(fileURLWithPath: String(fields[1])).standardizedFileURL.path] = kibibytes * 1_024
            }
            return sizes
        } catch {
            return [:]
        }
    }

    /// Simulator runtimes are mounted disk images. Walking their bundle path
    /// traverses the entire mounted OS and can take minutes. Volume capacity
    /// metadata gives an immediate used-size estimate without touching every
    /// file in the runtime.
    private func runtimeVolumeUsedBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let volumeURL = values.volume,
              volumeURL.standardizedFileURL.path != "/",
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else {
            return nil
        }
        return max(0, Int64(total - available))
    }

    private func runtimeDisplayName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}
