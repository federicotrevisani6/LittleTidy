import Foundation
import Testing
@testable import LittleTidyCore

@Suite("App Trash Watcher")
struct AppTrashWatcherTests {
    @Test("inspects app in Trash and locates related leftovers")
    func inspectsAppAndLocatesLeftovers() throws {
        let tempDir = try TemporaryDirectory().url
        let home = tempDir.appendingPathComponent("UserHome", isDirectory: true)
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let appSupport = library.appendingPathComponent("Application Support/com.example.TestApp", isDirectory: true)
        let caches = library.appendingPathComponent("Caches/com.example.TestApp", isDirectory: true)

        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)

        try Data(repeating: 0x41, count: 2048).write(to: appSupport.appendingPathComponent("data.sqlite"))
        try Data(repeating: 0x42, count: 1024).write(to: caches.appendingPathComponent("cache.db"))

        // Create .app bundle in trash
        let appURL = trash.appendingPathComponent("TestApp.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.TestApp</string>
            <key>CFBundleName</key>
            <string>TestApp</string>
            <key>CFBundleDisplayName</key>
            <string>Test App Pro</string>
            <key>CFBundleShortVersionString</key>
            <string>1.2.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let watcher = AppTrashWatcher(
            fileManager: .default,
            homeURL: home,
            trashURL: trash,
            monitor: MockTrashMonitor()
        )

        let event = watcher.inspectAppInTrash(at: appURL)
        #expect(event != nil)
        #expect(event?.bundleIdentifier == "com.example.TestApp")
        #expect(event?.displayName == "Test App Pro")
        #expect(event?.version == "1.2.0")
        #expect(event?.leftovers.count == 2)
        #expect((event?.totalLeftoverBytes ?? 0) >= 3072)
    }

    @Test("ignores apps with missing or invalid Info.plist")
    func ignoresAppsWithoutValidInfo() throws {
        let tempDir = try TemporaryDirectory().url
        let home = tempDir.appendingPathComponent("UserHome", isDirectory: true)
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        let brokenApp = trash.appendingPathComponent("Broken.app", isDirectory: true)
        try FileManager.default.createDirectory(at: brokenApp, withIntermediateDirectories: true)

        let watcher = AppTrashWatcher(
            fileManager: .default,
            homeURL: home,
            trashURL: trash,
            monitor: MockTrashMonitor()
        )

        let event = watcher.inspectAppInTrash(at: brokenApp)
        #expect(event == nil)
    }

    @Test("watcher fires callback when new app is moved to Trash")
    func watcherFiresCallbackOnNewApp() throws {
        let tempDir = try TemporaryDirectory().url
        let home = tempDir.appendingPathComponent("UserHome", isDirectory: true)
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let appSupport = library.appendingPathComponent("Application Support/com.example.NotifiedApp", isDirectory: true)

        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 500).write(to: appSupport.appendingPathComponent("state.json"))

        let mockMonitor = MockTrashMonitor()
        let watcher = AppTrashWatcher(
            fileManager: .default,
            homeURL: home,
            trashURL: trash,
            monitor: mockMonitor
        )

        let eventBox = EventBox()
        watcher.start { event in
            eventBox.add(event)
        }

        // Add app to trash after starting watcher
        let appURL = trash.appendingPathComponent("NotifiedApp.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.NotifiedApp</string>
            <key>CFBundleName</key>
            <string>NotifiedApp</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        mockMonitor.fireEvent(urls: [trash])

        let detected = eventBox.all
        #expect(detected.count == 1)
        #expect(detected.first?.bundleIdentifier == "com.example.NotifiedApp")
        #expect(detected.first?.leftovers.count == 1)

        watcher.stop()
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AppUninstallEvent] = []

    func add(_ event: AppUninstallEvent) {
        lock.withLock { events.append(event) }
    }

    var all: [AppUninstallEvent] {
        lock.withLock { events }
    }
}

private final class MockTrashMonitor: TrashFolderMonitoring, @unchecked Sendable {
    private var callback: (@Sendable ([URL]) -> Void)?

    func startMonitoring(trashURL: URL, onEvent: @escaping @Sendable ([URL]) -> Void) -> any TrashFolderMonitorSubscription {
        self.callback = onEvent
        return MockSubscription()
    }

    func fireEvent(urls: [URL]) {
        callback?(urls)
    }
}

private struct MockSubscription: TrashFolderMonitorSubscription {
    func cancel() {}
}
