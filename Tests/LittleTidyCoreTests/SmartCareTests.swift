import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Smart Care builder")
struct SmartCareBuilderTests {
    private func entry(_ path: String, _ bytes: Int64, _ tier: StorageRecommendation) -> SmartCareEntry {
        SmartCareEntry(path: path, bytes: bytes, tier: tier)
    }

    @Test func pathClaimedByHigherCardIsRemovedFromLowerCard() {
        let inputs = SmartCareInputs(entries: [
            .developer: [entry("/Users/a/.npm", 100, .recommended)],
            .caches: [entry("/Users/a/.npm", 100, .recommended), entry("/Users/a/Library/Caches/x", 50, .recommended)]
        ])
        let cards = SmartCareBuilder.cards(from: inputs)
        #expect(cards.first { $0.cardID == .caches }?.entries.map(\.path) == ["/Users/a/Library/Caches/x"])
        #expect(SmartCareBuilder.headline(for: cards).safeBytes == 150)
    }

    @Test func nestedPathsAreCountedOnce() {
        let inputs = SmartCareInputs(entries: [
            .developer: [entry("/Users/a/.cache/pip", 100, .recommended)],
            .caches: [entry("/Users/a/.cache", 400, .recommended)]
        ])
        let cards = SmartCareBuilder.cards(from: inputs)
        #expect(cards.first { $0.cardID == .caches }?.entries.isEmpty == true)
    }

    @Test func headlineExcludesReviewProtectedAndTrash() {
        let inputs = SmartCareInputs(entries: [
            .developer: [entry("/a", 10, .recommended), entry("/b", 20, .review), entry("/c", 30, .protected), entry("/d", 40, .unclassified)],
            .trash: [entry("/Users/a/.Trash/x", 999, .recommended)]
        ])
        let headline = SmartCareBuilder.headline(for: SmartCareBuilder.cards(from: inputs))
        #expect(headline.safeBytes == 10)
        #expect(headline.reviewBytes == 20)
    }

    @Test func needsAccessIsNeverReportedAsEmpty() {
        let inputs = SmartCareInputs(states: [.trash: .needsAccess("Full Disk Access")])
        let card = SmartCareBuilder.cards(from: inputs).first { $0.cardID == .trash }
        #expect(card?.state == .needsAccess("Full Disk Access"))
        #expect(card?.canClean == false)
    }

    @Test func cleanRequiresRecommendedBytes() {
        let reviewOnly = SmartCareCard(cardID: .aiTools, state: .ready, entries: [entry("/m", 5, .review)])
        let safe = SmartCareCard(cardID: .caches, state: .ready, entries: [entry("/c", 5, .recommended)])
        #expect(reviewOnly.canClean == false)
        #expect(safe.canClean == true)
    }

    @Test func emptyCardsCollapseToEmptyState() {
        let cards = SmartCareBuilder.cards(from: SmartCareInputs())
        #expect(cards.allSatisfy { $0.isEmpty })
    }
}

@Suite("Trash emptier")
struct TrashEmptierTests {
    private func makeTrash() throws -> (root: URL, trash: URL) {
        let temp = try TemporaryDirectory()
        let trash = temp.url.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (temp.url, trash)
    }

    @Test func nilSnapshotBlocksEverything() async throws {
        let (_, trash) = try makeTrash()
        let file = trash.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let result = await TrashEmptier(trashURL: trash) { nil }.empty()
        #expect(result.blockedReason != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removesChildrenAndReportsBytes() async throws {
        let (_, trash) = try makeTrash()
        try Data(repeating: 1, count: 10_000).write(to: trash.appendingPathComponent("a.bin"))
        let folder = trash.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: folder.appendingPathComponent("b.txt"))
        let result = await TrashEmptier(trashURL: trash) { OpenFileSnapshot(paths: []) }.empty()
        #expect(result.removed.count == 2)
        #expect(result.blockedReason == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    @Test func symlinkIsRemovedAndTargetSurvives() async throws {
        let (root, trash) = try makeTrash()
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let precious = outside.appendingPathComponent("precious.txt")
        try Data("keep".utf8).write(to: precious)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link"), withDestinationURL: outside)
        let result = await TrashEmptier(trashURL: trash) { OpenFileSnapshot(paths: []) }.empty()
        #expect(result.removed.count == 1)
        #expect(FileManager.default.fileExists(atPath: precious.path))
    }

    @Test func itemWithOpenFileIsSkippedWhileOthersAreRemoved() async throws {
        let (_, trash) = try makeTrash()
        let busy = trash.appendingPathComponent("busy", isDirectory: true)
        try FileManager.default.createDirectory(at: busy, withIntermediateDirectories: true)
        let busyFile = busy.appendingPathComponent("f.txt")
        try Data("z".utf8).write(to: busyFile)
        let other = trash.appendingPathComponent("other.txt")
        try Data("o".utf8).write(to: other)
        let snapshot = OpenFileSnapshot(paths: [busyFile.resolvingSymlinksInPath().path])
        let result = await TrashEmptier(trashURL: trash) { snapshot }.empty()
        #expect(result.skipped.count == 1)
        #expect(result.removed.count == 1)
        #expect(FileManager.default.fileExists(atPath: busyFile.path))
        #expect(!FileManager.default.fileExists(atPath: other.path))
    }

    @Test func foreignOwnedItemIsSkipped() async throws {
        let (_, trash) = try makeTrash()
        let file = trash.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        // A different user ID makes every file look foreign-owned.
        let result = await TrashEmptier(trashURL: trash, userID: getuid() &+ 12345) { OpenFileSnapshot(paths: []) }.empty()
        #expect(result.skipped.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func previewListsLastCleanupItemsFirst() throws {
        let (_, trash) = try makeTrash()
        let big = trash.appendingPathComponent("big.bin")
        let mine = trash.appendingPathComponent("mine.txt")
        try Data(repeating: 1, count: 100_000).write(to: big)
        try Data("m".utf8).write(to: mine)
        let preview = try TrashEmptier(trashURL: trash) { nil }.preview(lastCleanupPaths: [mine.path])
        #expect(preview.items.first?.url.lastPathComponent == "mine.txt")
        #expect(preview.fromLastCleanupCount == 1)
    }

    @Test func unreadableTrashThrowsInsteadOfReportingEmpty() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try TrashEmptier(trashURL: missing) { nil }.preview()
        }
    }
}

@Suite("Smart Care clean all safe")
struct SmartCareCleanPlannerTests {
    private func item(
        _ id: String,
        category: DeveloperStorageCategory = .derivedData,
        bytes: Int64 = 1_000,
        recommendation: StorageRecommendation = .recommended,
        mechanism: DeveloperCleanupMechanism = .trash,
        recoverability: StorageRecoverability = .recreatable,
        activity: StorageActivityState = .inactive
    ) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: id,
            category: category,
            name: id,
            detail: "",
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            bytes: bytes,
            activity: activity,
            recoverability: recoverability,
            cleanupMechanism: mechanism,
            consequence: .negligible,
            recommendation: recommendation,
            recommendationReason: ""
        )
    }

    @Test func onlyRecommendedItemsAreIncluded() {
        let plan = SmartCareCleanPlanner.plan(from: [
            item("safe"),
            item("review", recommendation: .review),
            item("protected", recommendation: .protected),
            item("unclassified", recommendation: .unclassified)
        ], xcodeIsRunning: false)
        #expect(plan.items.map(\.id) == ["safe"])
    }

    @Test func activeAndEmptyItemsAreLeftOut() {
        let plan = SmartCareCleanPlanner.plan(from: [
            item("busy", activity: .active),
            item("empty", bytes: 0),
            item("ok")
        ], xcodeIsRunning: false)
        #expect(plan.items.map(\.id) == ["ok"])
    }

    @Test func runtimeDeletionAndManualMechanismsAreNeverIncluded() {
        let plan = SmartCareCleanPlanner.plan(from: [
            item("runtime", category: .simulatorRuntimes, mechanism: .xcodeManaged),
            item("manual", mechanism: .manual),
            item("unsupported", mechanism: .unsupported)
        ], xcodeIsRunning: false)
        #expect(plan.isEmpty)
    }

    @Test func itemsThatNeedXcodeClosedAreSkippedWhileXcodeRuns() {
        let items = [
            item("device-support", category: .deviceSupport),
            item("derived", category: .derivedData),
            item("ai-cache", category: .aiCaches)
        ]
        let running = SmartCareCleanPlanner.plan(from: items, xcodeIsRunning: true)
        #expect(running.skipped.map(\.itemID) == ["device-support"])
        #expect(Set(running.items.map(\.id)) == ["derived", "ai-cache"])

        let closed = SmartCareCleanPlanner.plan(from: items, xcodeIsRunning: false)
        #expect(closed.skipped.isEmpty)
        #expect(closed.items.count == 3)
    }

    @Test func irreversibleItemsAreFlagged() {
        let trashOnly = SmartCareCleanPlanner.plan(from: [item("a")], xcodeIsRunning: false)
        #expect(trashOnly.hasIrreversibleItems == false)

        let withSimctl = SmartCareCleanPlanner.plan(from: [
            item("a"),
            item("device", category: .simulatorDevices, mechanism: .simctl, recoverability: .irreversible)
        ], xcodeIsRunning: false)
        #expect(withSimctl.hasIrreversibleItems)
        #expect(withSimctl.irreversibleItems.map(\.id) == ["device"])
    }

    @Test func groupsSplitDeveloperFromAITools() {
        let plan = SmartCareCleanPlanner.plan(from: [
            item("derived", bytes: 300),
            item("ai", category: .aiCaches, bytes: 200),
            item("derived2", bytes: 100)
        ], xcodeIsRunning: false)
        #expect(plan.groups.map(\.cardID) == [.developer, .aiTools])
        #expect(plan.groups.first { $0.cardID == .developer }?.bytes == 400)
        #expect(plan.groups.first { $0.cardID == .aiTools }?.itemCount == 1)
        #expect(plan.totalBytes == 600)
    }

    @Test func itemsAreOrderedLargestFirst() {
        let plan = SmartCareCleanPlanner.plan(from: [item("small", bytes: 1), item("big", bytes: 9)], xcodeIsRunning: false)
        #expect(plan.items.map(\.id) == ["big", "small"])
    }

    @Test func planTotalMatchesTheHeadlineSafeTotalForTheSameItems() {
        let items = [item("a", bytes: 700), item("b", category: .aiCaches, bytes: 300), item("r", bytes: 50, recommendation: .review)]
        let plan = SmartCareCleanPlanner.plan(from: items, xcodeIsRunning: false)
        var inputs = SmartCareInputs()
        inputs.entries[.developer] = items.filter { SmartCareCleanPlanner.cardID(for: $0) == .developer }
            .map { SmartCareEntry(path: $0.url!.path, bytes: $0.bytes, tier: $0.recommendation) }
        inputs.entries[.aiTools] = items.filter { SmartCareCleanPlanner.cardID(for: $0) == .aiTools }
            .map { SmartCareEntry(path: $0.url!.path, bytes: $0.bytes, tier: $0.recommendation) }
        let headline = SmartCareBuilder.headline(for: SmartCareBuilder.cards(from: inputs))
        #expect(plan.totalBytes == headline.safeBytes)
    }
}

@Suite("Cleanup summary")
struct CleanupSummaryTests {
    private func result(
        _ id: String,
        bytes: Int64 = 1_000,
        status: DeveloperStorageCleanupStatus = .removed,
        trash: Bool = false,
        message: String = "",
        original: String? = nil,
        trashPath: String? = nil
    ) -> DeveloperStorageCleanupResultItem {
        DeveloperStorageCleanupResultItem(
            itemID: id, name: id, bytes: bytes, status: status, message: message,
            movedToTrash: trash, originalPath: original, trashPath: trashPath
        )
    }

    private func item(_ id: String, category: DeveloperStorageCategory = .derivedData) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: id, category: category, name: id, detail: "", url: nil, bytes: 1_000,
            activity: .inactive, recoverability: .recreatable, cleanupMechanism: .trash,
            consequence: .negligible, recommendation: .recommended, recommendationReason: ""
        )
    }

    @Test func trashBytesAreNeverCountedAsFreedNow() {
        let summary = CleanupSummary.make(from: DeveloperStorageCleanupResult(items: [
            result("gone", bytes: 500),
            result("trashed", bytes: 9_000, trash: true, original: "/a", trashPath: "/b/.Trash/a")
        ]), items: [item("gone"), item("trashed")])
        #expect(summary.freedNowBytes == 500)
        #expect(summary.inTrashBytes == 9_000)
        #expect(summary.removedCount == 2)
    }

    @Test func snapshotHeldSpaceShowsOnlyWhenMeaningful() {
        // 1 GB removed for good, but free space grew by only 100 MB.
        let big = DeveloperStorageCleanupResult(
            items: [result("a", bytes: 1_000_000_000)],
            freeBytesBefore: 10_000_000_000, freeBytesAfter: 10_100_000_000)
        let held = CleanupSummary.make(from: big, items: [item("a")])
        #expect(held.heldBySnapshotBytes == 900_000_000)
        #expect(held.freedNowBytes == 100_000_000)

        // A small gap stays hidden and everything counts as freed.
        let small = DeveloperStorageCleanupResult(
            items: [result("a", bytes: 50_000_000)],
            freeBytesBefore: 10_000_000_000, freeBytesAfter: 10_040_000_000)
        let quiet = CleanupSummary.make(from: small, items: [item("a")])
        #expect(quiet.heldBySnapshotBytes == nil)
        #expect(quiet.freedNowBytes == 50_000_000)
    }

    @Test func skippedAndFailedKeepTheirReasons() {
        let summary = CleanupSummary.make(from: DeveloperStorageCleanupResult(items: [
            result("busy", status: .skipped, message: "Quit Xcode."),
            result("broken", status: .failed, message: "Permission denied.")
        ]), items: [])
        #expect(summary.skipped.first?.reason == "Quit Xcode.")
        #expect(summary.failed.first?.reason == "Permission denied.")
        #expect(summary.hasProblems)
        #expect(summary.removedCount == 0)
    }

    @Test func onlyTrashMovesWithPathsAreRestorable() {
        let summary = CleanupSummary.make(from: DeveloperStorageCleanupResult(items: [
            result("a", trash: true, original: "/x/a", trashPath: "/u/.Trash/a"),
            result("noPaths", trash: true),
            result("brew", trash: false)
        ]), items: [])
        #expect(summary.restorable.map(\.name) == ["a"])
        #expect(summary.irreversibleCount == 1)
    }

    @Test func linesSplitByCard() {
        let summary = CleanupSummary.make(from: DeveloperStorageCleanupResult(items: [
            result("dd", bytes: 300), result("ai", bytes: 200)
        ]), items: [item("dd"), item("ai", category: .aiCaches)])
        #expect(summary.lines.map(\.cardID) == [.developer, .aiTools])
        #expect(summary.lines.first { $0.cardID == .aiTools }?.bytes == 200)
    }

    @Test func oldResultsWithoutPathsStillDecode() throws {
        let json = #"{"items":[{"itemID":"a","name":"a","bytes":1,"status":"removed","message":"","movedToTrash":true,"allocatedBytes":1}]}"#
        let decoded = try JSONDecoder().decode(DeveloperStorageCleanupResult.self, from: Data(json.utf8))
        #expect(decoded.items.first?.originalPath == nil)
    }
}

@Suite("Trash restorer")
struct TrashRestorerTests {
    private func setup() throws -> (trash: URL, home: URL) {
        let temp = try TemporaryDirectory()
        let trash = temp.url.appendingPathComponent(".Trash", isDirectory: true)
        let home = temp.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (trash, home)
    }

    @Test func restoresIntoAFreePlace() throws {
        let (trash, home) = try setup()
        let inTrash = trash.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: inTrash)
        let original = home.appendingPathComponent("a.txt")
        let result = TrashRestorer().restore([RestorableItem(name: "a", originalURL: original, trashURL: inTrash)])
        #expect(result.restored.count == 1)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: inTrash.path))
    }

    @Test func neverOverwritesAnExistingItem() throws {
        let (trash, home) = try setup()
        let inTrash = trash.appendingPathComponent("a.txt")
        try Data("trash".utf8).write(to: inTrash)
        let original = home.appendingPathComponent("a.txt")
        try Data("new".utf8).write(to: original)
        let result = TrashRestorer().restore([RestorableItem(name: "a", originalURL: original, trashURL: inTrash)])
        #expect(result.restored.isEmpty)
        #expect(result.notRestored.count == 1)
        #expect(try String(contentsOf: original, encoding: .utf8) == "new")
        #expect(FileManager.default.fileExists(atPath: inTrash.path))
    }

    @Test func reportsItemsNoLongerInTheTrash() throws {
        let (trash, home) = try setup()
        let result = TrashRestorer().restore([
            RestorableItem(name: "gone", originalURL: home.appendingPathComponent("gone"), trashURL: trash.appendingPathComponent("gone"))
        ])
        #expect(result.notRestored.first?.reason == "It is no longer in the Trash.")
    }

    @Test func doesNotRecreateAMissingFolder() throws {
        let (trash, home) = try setup()
        let inTrash = trash.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: inTrash)
        let original = home.appendingPathComponent("missing/a.txt")
        let result = TrashRestorer().restore([RestorableItem(name: "a", originalURL: original, trashURL: inTrash)])
        #expect(result.restored.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("missing").path))
    }

    @Test func refusesItemsOutsideATrashFolder() throws {
        let (_, home) = try setup()
        let outside = home.appendingPathComponent("not-trash.txt")
        try Data("x".utf8).write(to: outside)
        let result = TrashRestorer().restore([
            RestorableItem(name: "x", originalURL: home.appendingPathComponent("moved.txt"), trashURL: outside)
        ])
        #expect(result.restored.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func aSymlinkMovesAsALinkAndItsTargetIsUntouched() throws {
        let (trash, home) = try setup()
        let target = home.appendingPathComponent("target.txt")
        try Data("keep".utf8).write(to: target)
        let link = trash.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let original = home.appendingPathComponent("link")
        let result = TrashRestorer().restore([RestorableItem(name: "link", originalURL: original, trashURL: link)])
        #expect(result.restored.count == 1)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: original.path)) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "keep")
    }
}

@Suite("Smart Care left-out items")
struct SmartCareLeftOutTests {
    @Test func leftOutEntriesAreNotInAnyTotalButStayVisible() {
        var inputs = SmartCareInputs()
        inputs.entries[.developer] = [
            SmartCareEntry(path: "/a", bytes: 1_000, tier: .recommended),
            SmartCareEntry(path: "/b", bytes: 400, tier: .recommended, isLeftOut: true),
            SmartCareEntry(path: "/c", bytes: 200, tier: .review)
        ]
        let cards = SmartCareBuilder.cards(from: inputs)
        let card = cards.first { $0.cardID == .developer }!
        #expect(card.recommendedBytes == 1_000)
        #expect(card.reviewBytes == 200)
        #expect(card.leftOutCount == 1)
        #expect(card.leftOutBytes == 400)
        #expect(card.itemCount == 3)
        #expect(SmartCareBuilder.headline(for: cards).safeBytes == 1_000)
    }

    @Test func aCardWithOnlyLeftOutItemsCannotBeCleaned() {
        let card = SmartCareCard(cardID: .developer, state: .ready, entries: [
            SmartCareEntry(path: "/b", bytes: 400, tier: .recommended, isLeftOut: true)
        ])
        #expect(card.canClean == false)
    }
}

@Suite("Permission guide")
struct PermissionGuideTests {
    @Test func confirmedOnlyWhenTheProbeSucceeds() {
        #expect(PermissionGuide.items(fullDiskAccessConfirmed: true).first?.state == .confirmed)
        #expect(PermissionGuide.items(fullDiskAccessConfirmed: false).first?.state == .notConfirmed)
        #expect(PermissionState.notConfirmed.label == "Not confirmed")
    }

    @Test func theGuideAppearsOnlyWhenSomethingIsNotConfirmedAndNotDismissed() {
        let missing = PermissionGuide.items(fullDiskAccessConfirmed: false)
        let granted = PermissionGuide.items(fullDiskAccessConfirmed: true)
        #expect(PermissionGuide.shouldPresent(items: missing, dismissedBefore: false))
        #expect(!PermissionGuide.shouldPresent(items: missing, dismissedBefore: true))
        #expect(!PermissionGuide.shouldPresent(items: granted, dismissedBefore: false))
    }

    @Test func affectedCardsAreListedOnlyForMissingPermissions() {
        #expect(PermissionGuide.affectedCards(in: PermissionGuide.items(fullDiskAccessConfirmed: false)) == [.trash, .iosBackups, .mailAttachments])
        #expect(PermissionGuide.affectedCards(in: PermissionGuide.items(fullDiskAccessConfirmed: true)).isEmpty)
    }

    @Test func everyPermissionExplainsItselfAndOpensSettings() {
        for kind in PermissionKind.allCases {
            #expect(!kind.unlocks.isEmpty)
            #expect(kind.settingsURL.absoluteString.hasPrefix("x-apple.systempreferences:"))
        }
    }
}
