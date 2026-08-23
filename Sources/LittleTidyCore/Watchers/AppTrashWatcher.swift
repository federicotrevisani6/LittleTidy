import CoreServices
import Foundation

/// Protocol for monitoring file system changes in a Trash directory.
public protocol TrashFolderMonitoring: Sendable {
    func startMonitoring(trashURL: URL, onEvent: @escaping @Sendable ([URL]) -> Void) -> any TrashFolderMonitorSubscription
}

public protocol TrashFolderMonitorSubscription: Sendable {
    func cancel()
}

/// FSEvents-based implementation for monitoring ~/.Trash changes on macOS.
public final class FSEventTrashFolderMonitor: TrashFolderMonitoring, @unchecked Sendable {
    public init() {}

    public func startMonitoring(trashURL: URL, onEvent: @escaping @Sendable ([URL]) -> Void) -> any TrashFolderMonitorSubscription {
        let subscription = FSEventSubscription(trashURL: trashURL, onEvent: onEvent)
        subscription.start()
        return subscription
    }
}

private final class FSEventSubscription: TrashFolderMonitorSubscription, @unchecked Sendable {
    private let trashURL: URL
    private let onEvent: @Sendable ([URL]) -> Void
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.littletidy.trashwatcher", qos: .utility)
    private var isCancelled = false
    private let lock = NSLock()

    init(trashURL: URL, onEvent: @escaping @Sendable ([URL]) -> Void) {
        self.trashURL = trashURL
        self.onEvent = onEvent
    }

    func start() {
        lock.withLock {
            guard streamRef == nil, !isCancelled else { return }

            let pathsToWatch = [trashURL.path as CFString] as CFArray
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
                guard let clientCallBackInfo else { return }
                let watcher = Unmanaged<FSEventSubscription>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                watcher.handleEvents(urls)
            }

            let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                1.0,
                flags
            ) else {
                return
            }

            self.streamRef = stream
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func handleEvents(_ urls: [URL]) {
        guard !isCancelled else { return }
        onEvent(urls)
    }

    func cancel() {
        lock.withLock {
            guard !isCancelled else { return }
            isCancelled = true
            if let stream = streamRef {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                streamRef = nil
            }
        }
    }

    deinit {
        cancel()
    }
}

/// Watches the macOS Trash for newly moved .app bundles and inspects ~/Library
/// for orphan leftovers.
public final class AppTrashWatcher: @unchecked Sendable {
    private let fileManager: FileManager
    private let trashURL: URL
    private let homeURL: URL
    private let appUsageAnalyzer: AppUsageAnalyzer
    private let monitor: any TrashFolderMonitoring
    private var subscription: (any TrashFolderMonitorSubscription)?
    private var processedAppPaths = Set<String>()
    private let stateLock = NSLock()
    private var onUninstallDetected: (@Sendable (AppUninstallEvent) -> Void)?

    public init(
        fileManager: FileManager = .default,
        homeURL: URL? = nil,
        trashURL: URL? = nil,
        monitor: any TrashFolderMonitoring = FSEventTrashFolderMonitor()
    ) {
        self.fileManager = fileManager
        let home = homeURL ?? fileManager.homeDirectoryForCurrentUser
        self.homeURL = home
        self.trashURL = trashURL ?? home.appendingPathComponent(".Trash", isDirectory: true)
        self.appUsageAnalyzer = AppUsageAnalyzer(fileManager: fileManager, homeDirectory: home)
        self.monitor = monitor
    }

    /// Starts observing the Trash folder.
    public func start(onUninstallDetected: @escaping @Sendable (AppUninstallEvent) -> Void) {
        stateLock.withLock {
            self.onUninstallDetected = onUninstallDetected
            // Pre-populate already existing items in Trash so we only notify on newly added apps
            populateExistingTrashApps()
            subscription?.cancel()
            subscription = monitor.startMonitoring(trashURL: trashURL) { [weak self] _ in
                self?.scanTrashForNewApps()
            }
        }
    }

    /// Stops observing the Trash folder.
    public func stop() {
        stateLock.withLock {
            subscription?.cancel()
            subscription = nil
            onUninstallDetected = nil
        }
    }

    /// Pre-populates the existing apps in Trash to avoid triggering on launch.
    private func populateExistingTrashApps() {
        guard let items = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items where item.pathExtension.lowercased() == "app" {
            processedAppPaths.insert(item.standardizedFileURL.path)
        }
    }

    /// Scans ~/.Trash for any newly added .app bundle not previously seen.
    public func scanTrashForNewApps() {
        guard let items = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var newlyFoundApps: [URL] = []
        stateLock.withLock {
            let currentPaths = Set(items.map { $0.standardizedFileURL.path })
            // Clean up paths that were permanently deleted or emptied from Trash
            processedAppPaths = processedAppPaths.intersection(currentPaths)

            for item in items where item.pathExtension.lowercased() == "app" {
                let path = item.standardizedFileURL.path
                if !processedAppPaths.contains(path) {
                    processedAppPaths.insert(path)
                    newlyFoundApps.append(item)
                }
            }
        }

        for appURL in newlyFoundApps {
            if let event = inspectAppInTrash(at: appURL) {
                stateLock.withLock {
                    onUninstallDetected?(event)
                }
            }
        }
    }

    /// Inspects an app bundle in the Trash, extracts its metadata, and searches for leftovers in ~/Library.
    public func inspectAppInTrash(at appURL: URL) -> AppUninstallEvent? {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlistURL) as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let displayName = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String

        let leftovers = appUsageAnalyzer.relatedAppData(bundleIdentifier: bundleIdentifier)
        let appSize = directoryAllocatedSize(appURL)

        return AppUninstallEvent(
            appURL: appURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            version: version,
            appSizeBytes: appSize,
            leftovers: leftovers
        )
    }

    private func directoryAllocatedSize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { partial, item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                return partial
            }
            return partial + Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
    }
}
