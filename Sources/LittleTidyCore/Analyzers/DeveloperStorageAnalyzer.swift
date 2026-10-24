import Darwin
import Foundation

public actor DeveloperStorageAnalyzer {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let commandRunner: any DeveloperToolCommandRunning
    private let policy: DeveloperStoragePolicy
    private let agentTemporaryRoot: URL
    private let homebrewExecutables: [URL]
    private let homebrewRunner: any DeveloperToolCommandRunning
    private let reclaimEstimator: APFSReclaimEstimator

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        commandRunner: any DeveloperToolCommandRunning = DeveloperToolCommandClient(),
        policy: DeveloperStoragePolicy = DeveloperStoragePolicy(),
        agentTemporaryRoot: URL? = nil,
        homebrewExecutables: [URL] = HomebrewCleanup.knownExecutables,
        homebrewRunner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 120, environment: HomebrewCleanup.environment),
        reclaimEstimator: APFSReclaimEstimator = APFSReclaimEstimator()
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.commandRunner = commandRunner
        self.policy = policy
        self.agentTemporaryRoot = agentTemporaryRoot ?? URL(fileURLWithPath: "/private/tmp/claude-\(getuid())", isDirectory: true)
        self.homebrewExecutables = homebrewExecutables
        self.homebrewRunner = homebrewRunner
        self.reclaimEstimator = reclaimEstimator
    }

    public func analyze() async throws -> DeveloperStorageInventory {
        var items: [DeveloperStorageItem] = []
        var issues: [DeveloperStorageAccessIssue] = []

        // brew cleanup --dry-run takes tens of seconds, so it runs detached,
        // in parallel with the filesystem measurements, and is awaited last.
        let brew = homebrewExecutables.first { fileManager.isExecutableFile(atPath: $0.path) }
        let runner = homebrewRunner
        let homebrewDryRun = brew.map { brew in
            Task.detached(priority: .utility) {
                try await runner.run(executable: brew, arguments: HomebrewCleanup.dryRunArguments)
            }
        }
        defer { homebrewDryRun?.cancel() }

        let developerRoot = homeDirectory.appendingPathComponent("Library/Developer", isDirectory: true)
        let xcodeRoot = developerRoot.appendingPathComponent("Xcode", isDirectory: true)

        appendDerivedDataProjects(
            of: xcodeRoot.appendingPathComponent("DerivedData", isDirectory: true),
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
        await appendXCTestDevices(
            developerRoot.appendingPathComponent("XCTestDevices", isDirectory: true),
            items: &items,
            issues: &issues
        )

        // Package Manager Caches
        let userLibraryCaches = homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        appendDirectory(
            userLibraryCaches.appendingPathComponent("org.swift.swiftpm", isDirectory: true),
            category: .packageCaches,
            name: "SwiftPM Package Cache",
            detail: "Cloned repositories and package manifests",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            homeDirectory.appendingPathComponent(".swiftpm/cache", isDirectory: true),
            category: .packageCaches,
            name: "SwiftPM Binary Cache",
            detail: "Precompiled binary targets and artifacts",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            userLibraryCaches.appendingPathComponent("CocoaPods", isDirectory: true),
            category: .packageCaches,
            name: "CocoaPods Cache",
            detail: "Cached pod specifications and downloads",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            userLibraryCaches.appendingPathComponent("Carthage", isDirectory: true),
            category: .packageCaches,
            name: "Carthage Cache",
            detail: "Binary frameworks and dependency cache",
            items: &items,
            issues: &issues
        )

        // Android Virtual Devices
        appendAndroidAVDChildren(
            of: homeDirectory.appendingPathComponent(".android/avd", isDirectory: true),
            items: &items,
            issues: &issues
        )

        // AI models. These are large and redownloadable, but never preselected.
        let userAppSupport = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dotCache = homeDirectory.appendingPathComponent(".cache", isDirectory: true)

        appendDirectory(
            homeDirectory.appendingPathComponent(".ollama/models", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "Ollama Models & Blobs",
            detail: "Local LLM weights and layers (~/.ollama/models)",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            dotCache.appendingPathComponent("huggingface/hub", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "Hugging Face Hub Models",
            detail: "Downloaded model weights and snapshot files",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            dotCache.appendingPathComponent("torch/hub", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "PyTorch Model Hub",
            detail: "Pretrained weights and checkpoints",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            dotCache.appendingPathComponent("mlx", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "MLX Model Cache",
            detail: "Apple Silicon optimized local model weights",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            userAppSupport.appendingPathComponent("LM Studio/models", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "LM Studio Models",
            detail: "Downloaded GGUF models",
            items: &items,
            issues: &issues
        )
        appendDirectory(
            userAppSupport.appendingPathComponent("jan/models", isDirectory: true),
            category: .aiModelsAndAgents,
            name: "Jan AI Local Models",
            detail: "Downloaded local models and engine binaries",
            items: &items,
            issues: &issues
        )
        // AI caches and logs. Keep exact paths so settings, credentials, and
        // memory files in the same product roots are never cleanup candidates.
        let aiCacheLocations: [(path: String, name: String, detail: String)] = [
            (".claude/cache", "Claude Code Cache", "Downloaded and generated cache data"),
            (".claude/debug", "Claude Code Debug Logs", "Regenerable diagnostic logs"),
            (".codex/log", "Codex Logs", "Regenerable local diagnostic logs"),
            (".codex/tmp", "Codex Temporary Data", "Temporary agent files"),
            ("Library/Application Support/Cursor/Cache", "Cursor Cache", "Regenerable application cache"),
            ("Library/Application Support/Cursor/Code Cache", "Cursor Code Cache", "Regenerable code cache"),
            ("Library/Application Support/Cursor/GPUCache", "Cursor GPU Cache", "Regenerable GPU cache"),
            ("Library/Application Support/Cursor/CachedData", "Cursor Cached Data", "Regenerable editor data"),
            ("Library/Application Support/Cursor/logs", "Cursor Logs", "Regenerable diagnostic logs"),
            ("Library/Application Support/Cursor/Crashpad", "Cursor Crash Reports", "Generated crash reports"),
            (".continue/index", "Continue IDE Code Index", "Local vector database and codebase index"),
            (".gemini/cache", "Gemini Agent Cache", "Downloaded models and execution cache")
        ]
        for location in aiCacheLocations {
            appendDirectory(
                homeDirectory.appendingPathComponent(location.path, isDirectory: true),
                category: .aiCaches,
                name: location.name,
                detail: location.detail,
                items: &items,
                issues: &issues
            )
        }

        // Session histories and workspace artifacts can contain screenshots,
        // documents, and tool outputs. They are removable only after review.
        let aiArtifactLocations: [(path: String, name: String, detail: String)] = [
            (".claude/projects", "Claude Code Project Sessions", "Transcripts, tool results, screenshots, and generated session artifacts"),
            (".codex/sessions", "Codex Active Sessions", "Active rollout histories and generated session artifacts"),
            (".codex/archived_sessions", "Codex Archived Sessions", "Archived rollout histories and generated session artifacts"),
            ("Library/Application Support/Cursor/User/workspaceStorage", "Cursor Workspace Storage", "Workspace indexes, chat history, and generated artifacts")
        ]
        for location in aiArtifactLocations {
            appendDirectory(
                homeDirectory.appendingPathComponent(location.path, isDirectory: true),
                category: .aiGeneratedArtifacts,
                name: location.name,
                detail: location.detail,
                items: &items,
                issues: &issues
            )
        }

        appendAgentTemporaryBuilds(items: &items, issues: &issues)
        appendDirectory(
            xcodeRoot.appendingPathComponent("UserData/Previews", isDirectory: true),
            category: .aiGeneratedArtifacts,
            name: "Xcode Preview Environments",
            detail: "Preview environments can be recreated, but may contain simulator app data. Review before cleaning.",
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

        // A symbolic link is never a cleanup candidate: it can point at a
        // location already listed (~/.swiftpm/cache links to
        // ~/Library/Caches/org.swift.swiftpm) or outside every known root.
        items = items.filter { item in item.url.map { !isSymbolicLink($0) } ?? true }
        items = items.map(estimatingClonedStorage)
        if let brew, let homebrewDryRun {
            await appendHomebrewCleanup(brew: brew, dryRun: homebrewDryRun, items: &items, issues: &issues)
        }
        let latestLocalSnapshotAt = await latestLocalSnapshot()

        return DeveloperStorageInventory(
            items: items.sorted { lhs, rhs in
                lhs.bytes == rhs.bytes
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.bytes > rhs.bytes
            },
            accessIssues: issues,
            simulatorToolAvailable: simulatorResult.toolAvailable,
            latestLocalSnapshotAt: latestLocalSnapshotAt
        )
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// Read-only. A failure only means the explanation is not shown.
    private func latestLocalSnapshot() async -> Date? {
        guard let result = try? await commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/tmutil"),
            arguments: LocalSnapshotInventory.listArguments
        ) else {
            return nil
        }
        return LocalSnapshotInventory.parseSnapshotDates(result.standardOutput).last
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
                    // The same model usually exists once per installed runtime,
                    // so the runtime is part of the name, not just the detail.
                    name: "\(device.name) · \(runtimeDisplayName(device.runtimeIdentifier))",
                    detail: device.state,
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

    /// Simulator devices and XCTest clones are APFS clones, and a local snapshot
    /// holds older blocks of any item, so allocated size can overstate what
    /// removal frees. Every preselected item is estimated, so the guaranteed
    /// total never relies on allocated size; review-only items are estimated
    /// only for the clone-heavy device categories to keep scans short.
    private func estimatingClonedStorage(_ item: DeveloperStorageItem) -> DeveloperStorageItem {
        let isDevice = item.category == .simulatorDevices || item.category == .xctestDevices
        guard item.recommendation == .recommended || (isDevice && item.recommendation == .review),
              item.bytes > 0,
              let url = item.url,
              !Task.isCancelled else {
            return item
        }
        return item.withMinimumReclaimableBytes(reclaimEstimator.minimumReclaimableBytes(at: url))
    }

    /// One item per project, so a running Xcode blocks only the projects it
    /// has open. Shared caches such as ModuleCache.noindex appear separately.
    private func appendDerivedDataProjects(
        of root: URL,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        do {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                try Task.checkCancellation()
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let name: String
                let detail: String
                if let workspacePath = derivedDataWorkspacePath(child) {
                    name = URL(fileURLWithPath: workspacePath).deletingPathExtension().lastPathComponent
                    detail = fileManager.fileExists(atPath: workspacePath)
                        ? "Build data for \(abbreviatingHome(workspacePath))"
                        : "Project no longer exists at \(abbreviatingHome(workspacePath))"
                } else if let projectName = derivedDataProjectName(child.lastPathComponent) {
                    // Some project folders, for example one holding only
                    // SourcePackages, have no info.plist to name the workspace.
                    name = projectName
                    detail = "Build data for \(projectName) · project location not recorded by Xcode"
                } else {
                    name = child.lastPathComponent
                    detail = "Shared Xcode build data"
                }
                items.append(makeItem(
                    id: "path:\(child.standardizedFileURL.path)",
                    category: .derivedData,
                    name: name,
                    detail: detail,
                    url: child,
                    externalIdentifier: nil,
                    isAvailable: true,
                    decision: policy.decision(for: .derivedData),
                    issues: &issues
                ))
            }
        } catch is CancellationError {
            return
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: root.path, message: error.localizedDescription))
        }
    }

    /// Xcode names per-project folders "<Name>-<28 lowercase letters>".
    /// Shared caches such as ModuleCache.noindex do not match.
    private func derivedDataProjectName(_ folderName: String) -> String? {
        guard let match = folderName.wholeMatch(of: /(.+)-[a-z]{28}/) else { return nil }
        return String(match.1)
    }

    private func derivedDataWorkspacePath(_ folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("info.plist")),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return nil
        }
        return plist["WorkspacePath"] as? String
    }

    private func abbreviatingHome(_ path: String) -> String {
        let home = homeDirectory.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// XCTest clones are registered in simctl's "testing" device set, which
    /// gives a supported removal path and live Booted state. Folders simctl
    /// does not list stay unclassified. If simctl is unavailable, the whole
    /// directory is reported for diagnosis only, as before.
    private func appendXCTestDevices(
        _ root: URL,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) async {
        guard fileManager.fileExists(atPath: root.path) else { return }
        let devices: [SimulatorDeviceRecord]
        do {
            let result = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "--set", "testing", "list", "devices", "--json"]
            )
            devices = try SimulatorInventoryParser().parse(result.standardOutput).devices
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: "/usr/bin/xcrun simctl --set testing", message: error.localizedDescription))
            items.append(makeItem(
                id: "path:\(root.standardizedFileURL.path)",
                category: .xctestDevices,
                name: "XCTest Devices",
                detail: "Test device environments and data",
                url: root,
                externalIdentifier: nil,
                isAvailable: true,
                decision: policy.unverifiedXCTestDecision(),
                issues: &issues
            ))
            return
        }

        let testSessionActive = devices.hasActiveTestSession
        let deviceURLs = devices.map { root.appendingPathComponent($0.udid, isDirectory: true) }
        let measuredBytes = allocatedBytesUsingDU(at: deviceURLs.filter { fileManager.fileExists(atPath: $0.path) })
        for (device, url) in zip(devices, deviceURLs) {
            let exists = fileManager.fileExists(atPath: url.path)
            let isActive = device.state.localizedCaseInsensitiveCompare("Booted") == .orderedSame
            items.append(makeItem(
                id: "xctest-device:\(device.udid)",
                category: .xctestDevices,
                name: "\(device.name) · \(runtimeDisplayName(device.runtimeIdentifier))",
                detail: device.state + (exists ? "" : " · Folder already removed"),
                url: exists ? url : nil,
                externalIdentifier: device.udid,
                isAvailable: device.isAvailable,
                decision: testSessionActive && !isActive
                    ? policy.xctestSessionActiveDecision()
                    : policy.decision(for: .xctestDevices, isAvailable: device.isAvailable, isActive: isActive),
                premeasuredBytes: exists ? (measuredBytes[url.standardizedFileURL.path] ?? 0) : 0
            ))
        }

        let registered = Set(devices.map(\.udid))
        let children = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children where !registered.contains(child.lastPathComponent) {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let item = makeItem(
                id: "path:\(child.standardizedFileURL.path)",
                category: .xctestDevices,
                name: child.lastPathComponent,
                detail: "XCTest data not registered with simctl",
                url: child,
                externalIdentifier: nil,
                isAvailable: true,
                decision: policy.unverifiedXCTestDecision(),
                issues: &issues
            )
            if item.bytes >= 1_000_000 {
                items.append(item)
            }
        }
    }

    /// Homebrew reports reclaimable space itself with a dry run. Its own
    /// cache folder is not listed here, so the space is not counted twice.
    private func appendHomebrewCleanup(
        brew: URL,
        dryRun: Task<DeveloperToolCommandResult, any Error>,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) async {
        do {
            let result = try await dryRun.value
            guard let bytes = HomebrewCleanup.parseReclaimedBytes(result.standardOutput), bytes > 0 else { return }
            let decision = policy.homebrewCleanupDecision()
            items.append(DeveloperStorageItem(
                id: "homebrew-cleanup:\(brew.path)",
                category: .packageCaches,
                name: "Homebrew Old Versions & Downloads",
                detail: "Estimated by brew cleanup --dry-run",
                url: nil,
                bytes: bytes,
                activity: decision.activity,
                recoverability: decision.recoverability,
                cleanupMechanism: decision.mechanism,
                consequence: decision.consequence,
                recommendation: decision.recommendation,
                recommendationReason: decision.reason,
                externalIdentifier: brew.path,
                isAvailable: true
            ))
        } catch is CancellationError {
            return
        } catch {
            issues.append(DeveloperStorageAccessIssue(path: "\(brew.path) cleanup --dry-run", message: error.localizedDescription))
        }
    }

    private func appendAgentTemporaryBuilds(items: inout [DeveloperStorageItem], issues: inout [DeveloperStorageAccessIssue]) {
        guard fileManager.fileExists(atPath: agentTemporaryRoot.path) else { return }
        var accessErrors: [DeveloperStorageAccessIssue] = []
        guard let enumerator = fileManager.enumerator(
            at: agentTemporaryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                accessErrors.append(DeveloperStorageAccessIssue(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else {
            issues.append(DeveloperStorageAccessIssue(path: agentTemporaryRoot.path, message: "Unable to read agent temporary data; size is unknown."))
            return
        }
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let depth = enumerator.level
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true || depth > 4 {
                enumerator.skipDescendants(); continue
            }
            guard values?.isDirectory == true else { continue }
            let plistURL = url.appendingPathComponent("info.plist")
            let build = url.appendingPathComponent("Build", isDirectory: true)
            guard fileManager.fileExists(atPath: build.path),
                  let data = try? Data(contentsOf: plistURL),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  plist["WorkspacePath"] is String else { continue }
            // Recognition requires an Xcode workspace marker, not a folder name.
            // Agent sessions, worktrees, and scripts are not cache candidates.
            enumerator.skipDescendants()
            let decision = DeveloperStorageDecision(
                activity: .unknown, recoverability: .recreatable, mechanism: .trash,
                consequence: .temporarySlowdown, recommendation: .review,
                reason: "Xcode build output created in a Claude temporary session. Stop the owning task before moving it to Trash; the next build recreates it."
            )
            items.append(makeItem(
                id: "path:\(url.standardizedFileURL.path)", category: .aiGeneratedArtifacts,
                name: "Claude build data: \(url.lastPathComponent)",
                detail: "Recognized Xcode DerivedData inside an agent temporary session",
                url: url, externalIdentifier: nil, isAvailable: true,
                decision: decision, issues: &issues
            ))
        }
        issues.append(contentsOf: accessErrors)
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

    private func appendAndroidAVDChildren(
        of root: URL,
        items: inout [DeveloperStorageItem],
        issues: inout [DeveloperStorageAccessIssue]
    ) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        do {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for child in children where child.pathExtension.lowercased() == "avd" {
                try Task.checkCancellation()
                let decision = policy.decision(for: .androidEmulators)
                items.append(makeItem(
                    id: "path:\(child.standardizedFileURL.path)",
                    category: .androidEmulators,
                    name: child.deletingPathExtension().lastPathComponent,
                    detail: "Android Virtual Device (AVD)",
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

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" becomes "iOS 27.2".
    static func runtimeDisplayName(_ identifier: String) -> String {
        let parts = identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return parts.joined(separator: " ") }
        return "\(platform) \(parts.dropFirst().joined(separator: "."))"
    }

    private func runtimeDisplayName(_ identifier: String) -> String {
        Self.runtimeDisplayName(identifier)
    }
}
