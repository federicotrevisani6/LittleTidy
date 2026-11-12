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
