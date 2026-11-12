import Foundation
import Testing
@testable import LittleTidyCore

private func makeDir(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func write(_ url: URL, bytes: Int = 4_000, daysOld: Int = 0, now: Date = Date()) throws {
    try makeDir(url.deletingLastPathComponent())
    try Data(repeating: 1, count: bytes).write(to: url)
    let date = Calendar.current.date(byAdding: .day, value: -daysOld, to: now)!
    try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
}

@Suite("Downloads clutter")
struct DownloadsClutterTests {
    private func analyzer(_ downloads: URL, apps: Set<String> = [], now: Date = Date()) -> DownloadsClutterAnalyzer {
        DownloadsClutterAnalyzer(downloads: downloads, now: { now }, installedAppNames: { apps })
    }

    @Test func installerOlderThanThirtyDaysIsListedAndYoungerIsNot() throws {
        let dir = try TemporaryDirectory().url
        try write(dir.appendingPathComponent("old.dmg"), daysOld: 31)
        try write(dir.appendingPathComponent("young.dmg"), daysOld: 29)
        let items = try analyzer(dir).analyze()
        #expect(items.map(\.name) == ["old.dmg"])
        #expect(items.first?.tier == .review)
    }

    @Test func nothingModifiedInTheLastSevenDaysIsListed() throws {
        let dir = try TemporaryDirectory().url
        try write(dir.appendingPathComponent("new.pkg"), daysOld: 2)
        #expect(try analyzer(dir).analyze().isEmpty)
    }

    @Test func installersOfInstalledAppsComeFirstAndSayWhy() throws {
        let dir = try TemporaryDirectory().url
        try write(dir.appendingPathComponent("Big Thing.dmg"), bytes: 400_000, daysOld: 40)
        try write(dir.appendingPathComponent("Firefox 120.0.dmg"), bytes: 4_000, daysOld: 40)
        let items = try analyzer(dir, apps: ["Firefox"]).analyze()
        #expect(items.first?.name == "Firefox 120.0.dmg")
        #expect(items.first?.reason.hasPrefix("An app with this name") == true)
    }

    @Test func appNameMatchingUsesWholeLeadingWords() {
        #expect(DownloadsClutterAnalyzer.matchesInstalledApp("Firefox 120.0", apps: ["firefox"]))
        #expect(!DownloadsClutterAnalyzer.matchesInstalledApp("Google Chrome", apps: ["go"]))
        #expect(!DownloadsClutterAnalyzer.matchesInstalledApp("Firefoxy", apps: ["firefox"]))
    }

    @Test func zipIsListedOnlyWithAnExpandedSiblingAndOlderThanSixtyDays() throws {
        let dir = try TemporaryDirectory().url
        try write(dir.appendingPathComponent("Project.zip"), daysOld: 61)
        try makeDir(dir.appendingPathComponent("Project"))
        try write(dir.appendingPathComponent("Alone.zip"), daysOld: 90)
        try write(dir.appendingPathComponent("Fresh.zip"), daysOld: 20)
        try makeDir(dir.appendingPathComponent("Fresh"))
        let items = try analyzer(dir).analyze()
        #expect(items.map(\.name) == ["Project.zip"])
    }

    @Test func symlinksAndMissingFolderAreHandled() throws {
        let dir = try TemporaryDirectory().url
        let target = dir.appendingPathComponent("real.dmg")
        try write(target, daysOld: 50)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.dmg"), withDestinationURL: target)
        let names = try analyzer(dir).analyze().map(\.name)
        #expect(names == ["real.dmg"])
        #expect(try analyzer(dir.appendingPathComponent("missing")).analyze().isEmpty)
    }
}

@Suite("iOS backups")
struct IOSBackupTests {
    private func writeBackup(_ root: URL, folder: String, device: String?, date: Date, encrypted: Bool = false) throws {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try makeDir(dir)
        try Data(repeating: 2, count: 8_000).write(to: dir.appendingPathComponent("blob"))
        if let device {
            let info: [String: Any] = ["Device Name": device, "Product Version": "19.1", "Last Backup Date": date]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
            try PropertyListSerialization.data(fromPropertyList: ["IsEncrypted": encrypted], format: .xml, options: 0)
                .write(to: dir.appendingPathComponent("Manifest.plist"))
        }
    }

    @Test func readsDeviceMetadataAndMarksOnlyReviewTier() throws {
        let root = try TemporaryDirectory().url
        try writeBackup(root, folder: "A", device: "Test iPhone", date: Date())
        let items = try IOSBackupAnalyzer(backupRoot: root).analyze()
        #expect(items.count == 1)
        #expect(items[0].name == "Test iPhone")
        #expect(items[0].tier == .review)
        #expect(items[0].detail.contains("iOS 19.1"))
        #expect(items[0].consequence.contains("cannot be recovered"))
    }

    @Test func aFolderWithoutAReadableInfoPlistIsUnclassified() throws {
        let root = try TemporaryDirectory().url
        try writeBackup(root, folder: "mystery", device: nil, date: Date())
        let item = try IOSBackupAnalyzer(backupRoot: root).analyze().first
        #expect(item?.tier == .unclassified)
        #expect(item?.isSelectable == false)
    }

    @Test func onlyTheNewestBackupOfADeviceGetsTheMostRecentWarning() throws {
        let root = try TemporaryDirectory().url
        let old = Date(timeIntervalSinceNow: -86_400 * 90)
        try writeBackup(root, folder: "old", device: "Phone", date: old)
        try writeBackup(root, folder: "new", device: "Phone", date: Date())
        let items = try IOSBackupAnalyzer(backupRoot: root).analyze()
        let warned = items.filter { $0.warning?.contains("most recent") == true }
        #expect(warned.count == 1)
        #expect(warned.first?.url.lastPathComponent == "new")
    }

    @Test func encryptedBackupsCarryTheEncryptedWarning() throws {
        let root = try TemporaryDirectory().url
        try writeBackup(root, folder: "e", device: "Phone", date: Date(), encrypted: true)
        let item = try IOSBackupAnalyzer(backupRoot: root).analyze().first
        #expect(item?.warning?.contains("Encrypted") == true)
    }

    @Test func missingRootIsEmptyAndUnreadableRootNeedsAccess() throws {
        #expect(try IOSBackupAnalyzer(backupRoot: URL(fileURLWithPath: "/nonexistent-\(UUID())")).analyze().isEmpty)
        let root = try TemporaryDirectory().url
        try makeDir(root.appendingPathComponent("x"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        #expect(throws: EverydayAccessError.needsAccess) { try IOSBackupAnalyzer(backupRoot: root).analyze() }
    }
}

@Suite("Mail downloads")
struct MailDownloadsTests {
    @Test func aCopyEditedAfterItWasSavedIsProtected() throws {
        let folder = try TemporaryDirectory().url
        let now = Date()
        try write(folder.appendingPathComponent("UUID1/report.pdf"), now: now)
        try write(folder.appendingPathComponent("UUID2/edited.docx"), now: now)
        let edited = folder.appendingPathComponent("UUID2/edited.docx")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(3_600)], ofItemAtPath: edited.path)
        let items = try MailDownloadsAnalyzer(folder: folder).analyze()
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        #expect(byName["report.pdf"]?.tier == .review)
        #expect(byName["edited.docx"]?.tier == .protected)
        #expect(byName["edited.docx"]?.isSelectable == false)
    }

    @Test func missingFolderIsEmpty() throws {
        #expect(try MailDownloadsAnalyzer(folder: URL(fileURLWithPath: "/nonexistent-\(UUID())")).analyze().isEmpty)
    }
}

private struct FakeActivity: EverydayActivityChecking {
    var mailRunning = false
    var snapshot: OpenFileSnapshot? = OpenFileSnapshot(paths: [])
    func isMailRunning() async -> Bool { mailRunning }
    func openFileSnapshot() async -> OpenFileSnapshot? { snapshot }
}

@Suite("Everyday space cleanup")
struct EverydayCleanupTests {
    private func item(_ url: URL, kind: EverydaySpaceKind = .installers, tier: StorageRecommendation = .review) -> EverydaySpaceItem {
        EverydaySpaceItem(kind: kind, name: url.lastPathComponent, detail: "", url: url, bytes: 4_000, tier: tier, reason: "", consequence: "")
    }

    /// A trash that moves into a temp folder, never the real Trash.
    private func fakeTrash(_ folder: URL) -> EverydaySpaceCleanupExecutor.Trasher {
        { url in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    private func setup() throws -> (root: URL, trash: URL) {
        let temp = try TemporaryDirectory().url
        let root = temp.appendingPathComponent("Downloads")
        try makeDir(root)
        return (root, temp.appendingPathComponent(".Trash"))
    }

    @Test func movesAReviewItemToTheTrashAndRecordsWhereItWent() async throws {
        let (root, trash) = try setup()
        let file = root.appendingPathComponent("a.dmg")
        try write(file)
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(file)])
        #expect(result.items.first?.status == .removed)
        #expect(result.items.first?.movedToTrash == true)
        #expect(result.items.first?.originalPath == file.path)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aMissingSnapshotBlocksEverything() async throws {
        let (root, trash) = try setup()
        let file = root.appendingPathComponent("a.dmg")
        try write(file)
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(snapshot: nil), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(file)])
        #expect(result.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func anItemWithAnOpenFileIsSkipped() async throws {
        let (root, trash) = try setup()
        let file = root.appendingPathComponent("a.dmg")
        try write(file)
        let snapshot = OpenFileSnapshot(paths: [file.resolvingSymlinksInPath().path])
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(snapshot: snapshot), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(file)])
        #expect(result.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func mailAttachmentsWaitForMailToQuit() async throws {
        let (root, trash) = try setup()
        let file = root.appendingPathComponent("UUID/a.pdf")
        try write(file)
        let folder = root.appendingPathComponent("UUID")
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(mailRunning: true), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(folder, kind: .mailDownloads)])
        #expect(result.items.first?.status == .skipped)
        #expect(result.items.first?.message.contains("Quit Mail") == true)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func protectedAndUnclassifiedItemsAreNeverRemoved() async throws {
        let (root, trash) = try setup()
        let a = root.appendingPathComponent("a.bin"), b = root.appendingPathComponent("b.bin")
        try write(a); try write(b)
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(a, tier: .protected), item(b, tier: .unclassified)])
        #expect(result.items.allSatisfy { $0.status == .skipped })
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
    }

    @Test func itemsOutsideTheAllowedRootsAndSymlinksAreRefused() async throws {
        let (root, trash) = try setup()
        let outsideDir = try TemporaryDirectory().url
        let outside = outsideDir.appendingPathComponent("x.dmg")
        try write(outside)
        let target = outsideDir.appendingPathComponent("target.dmg")
        try write(target)
        let link = root.appendingPathComponent("link.dmg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(), trash: fakeTrash(trash))
        let result = await executor.execute(items: [item(outside), item(link)])
        #expect(result.items.allSatisfy { $0.status == .skipped })
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func aFailingMoveIsReportedAndTheNextItemStillRuns() async throws {
        let (root, trash) = try setup()
        let bad = root.appendingPathComponent("bad.dmg"), good = root.appendingPathComponent("good.dmg")
        try write(bad); try write(good)
        let base = fakeTrash(trash)
        let flaky: EverydaySpaceCleanupExecutor.Trasher = { url in
            if url.lastPathComponent == "bad.dmg" { throw CocoaError(.fileWriteNoPermission) }
            return try base(url)
        }
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(), trash: flaky)
        let result = await executor.execute(items: [item(bad), item(good)])
        #expect(result.items.map(\.status) == [.failed, .removed])
    }
}

@Suite("App leftovers")
struct OrphanLeftoverTests {
    private struct Fixture {
        let home: URL
        let apps: URL
    }

    private func fixture() throws -> Fixture {
        let root = try TemporaryDirectory().url
        let home = root.appendingPathComponent("home")
        let apps = root.appendingPathComponent("Apps")
        try makeDir(home.appendingPathComponent("Library"))
        try makeDir(apps)
        return Fixture(home: home, apps: apps)
    }

    private func makeApp(_ f: Fixture, name: String, id: String, nested: [(String, String)] = []) throws {
        let contents = f.apps.appendingPathComponent("\(name).app/Contents")
        try makeDir(contents)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        for (folder, nestedID) in nested {
            let bundle = contents.appendingPathComponent("\(folder)/Helper.app/Contents")
            try makeDir(bundle)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": nestedID], format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Info.plist"))
        }
    }

    private func leftover(_ f: Fixture, folder: String, name: String, daysOld: Int = 120) throws {
        let dir = f.home.appendingPathComponent("Library/\(folder)")
        try makeDir(dir)
        let item = dir.appendingPathComponent(name)
        if name.hasSuffix(".plist") {
            try Data(repeating: 1, count: 2_000).write(to: item)
        } else {
            try makeDir(item)
            try Data(repeating: 1, count: 5_000).write(to: item.appendingPathComponent("data"))
        }
        let date = Calendar.current.date(byAdding: .day, value: -daysOld, to: Date())!
        for url in [item, item.appendingPathComponent("data")] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func analyzer(_ f: Fixture, running: Set<String> = [], spotlight: [URL]? = []) -> OrphanLeftoverAnalyzer {
        OrphanLeftoverAnalyzer(home: f.home, appRoots: [f.apps], runningBundleIDs: { running }, spotlightApps: { spotlight })
    }

    @Test func anIdWithNoInstalledAppIsListedWithItsEvidence() async throws {
        let f = try fixture()
        try leftover(f, folder: "Application Support", name: "com.gone.tool")
        let result = try await analyzer(f).analyze()
        #expect(result.items.map(\.name) == ["com.gone.tool"])
        #expect(result.items.first?.tier == .review)
        #expect(result.items.first?.reason.contains("No app with this ID") == true)
        #expect(result.items.first?.bundleID == "com.gone.tool")
    }

    @Test func installedAndNestedAndSuffixedIdsAreNotListed() async throws {
        let f = try fixture()
        try makeApp(f, name: "Main", id: "com.here.main", nested: [("Library/LoginItems", "com.here.launcher"), ("XPCServices", "com.other.xpc")])
        for name in ["com.here.main", "com.here.launcher", "com.other.xpc", "com.here.main.helper", "com.here.main.savedState"] {
            try leftover(f, folder: "Caches", name: name)
        }
        try leftover(f, folder: "Caches", name: "com.gone.real")
        let result = try await analyzer(f).analyze()
        #expect(result.items.map(\.name) == ["com.gone.real"])
    }

    @Test func aRunningAppsDataIsNeverListed() async throws {
        let f = try fixture()
        try leftover(f, folder: "Application Support", name: "com.run.ning")
        let result = try await analyzer(f, running: ["com.RUN.ning"]).analyze()
        #expect(result.items.isEmpty)
    }

    @Test func appleIdsGroupContainersAndShortNamesAreNeverListed() async throws {
        let f = try fixture()
        try leftover(f, folder: "Application Support", name: "com.apple.something")
        try leftover(f, folder: "Group Containers", name: "group.com.gone.shared")
        try leftover(f, folder: "Application Support", name: "Firefox")
        try leftover(f, folder: "Application Support", name: "com.short")
        #expect(try await analyzer(f).analyze().items.isEmpty)
    }

    @Test func nothingModifiedInTheLastNinetyDaysIsListed() async throws {
        let f = try fixture()
        try leftover(f, folder: "Application Support", name: "com.gone.recent", daysOld: 30)
        try leftover(f, folder: "Application Support", name: "com.gone.old", daysOld: 100)
        #expect(try await analyzer(f).analyze().items.map(\.name) == ["com.gone.old"])
    }

    @Test func preferencesAndSavedStateNamesAreMatchedByTheirIdentifier() async throws {
        let f = try fixture()
        try leftover(f, folder: "Preferences", name: "com.gone.prefs.plist")
        try leftover(f, folder: "Saved Application State", name: "com.gone.state.savedState")
        let names = try await analyzer(f).analyze().items.map(\.name).sorted()
        #expect(names == ["com.gone.prefs", "com.gone.state"])
    }

    @Test func anAppFoundOnlyThroughSpotlightCountsAsInstalled() async throws {
        let f = try fixture()
        let external = try TemporaryDirectory().url.appendingPathComponent("Elsewhere")
        try makeDir(external)
        let other = Fixture(home: f.home, apps: external)
        try makeApp(other, name: "Far", id: "com.far.away")
        try leftover(f, folder: "Caches", name: "com.far.away")
        let result = try await analyzer(f, spotlight: [external.appendingPathComponent("Far.app")]).analyze()
        #expect(result.items.isEmpty)
    }

    @Test func whenSpotlightCannotAnswerNothingIsListed() async throws {
        let f = try fixture()
        try leftover(f, folder: "Application Support", name: "com.gone.tool")
        let result = try await analyzer(f, spotlight: nil).analyze()
        #expect(result.items.isEmpty)
        #expect(result.problem == .cannotVerify)
    }

    @Test func symlinksAreSkipped() async throws {
        let f = try fixture()
        let target = f.home.appendingPathComponent("elsewhere")
        try makeDir(target)
        let dir = f.home.appendingPathComponent("Library/Application Support")
        try makeDir(dir)
        let link = dir.appendingPathComponent("com.gone.link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let date = Calendar.current.date(byAdding: .day, value: -200, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        #expect(try await analyzer(f).analyze().items.isEmpty)
    }

    @Test func identifierShapeAndMatchingRules() {
        #expect(OrphanLeftoverAnalyzer.isReverseDNS("com.vendor.app"))
        #expect(!OrphanLeftoverAnalyzer.isReverseDNS("com.vendor"))
        #expect(!OrphanLeftoverAnalyzer.isReverseDNS("Some App"))
        #expect(OrphanLeftoverAnalyzer.isInstalled("com.a.b.helper", in: ["com.a.b"]))
        #expect(!OrphanLeftoverAnalyzer.isInstalled("com.a.bee", in: ["com.a.b"]))
    }

    @Test func theExecutorSkipsLeftoversOfARunningApp() async throws {
        let temp = try TemporaryDirectory().url
        let root = temp.appendingPathComponent("Library/Caches")
        try makeDir(root)
        let file = root.appendingPathComponent("com.gone.tool")
        try makeDir(file)
        let item = EverydaySpaceItem(kind: .appLeftovers, name: "com.gone.tool", detail: "", url: file, bytes: 10, tier: .review,
                                     reason: "", consequence: "", bundleID: "com.gone.tool")
        let executor = EverydaySpaceCleanupExecutor(allowedRoots: [root], activity: FakeActivity(), runningBundleIDs: { ["com.gone.tool"] }, trash: { _ in nil })
        let result = await executor.execute(items: [item])
        #expect(result.items.first?.status == .skipped)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
