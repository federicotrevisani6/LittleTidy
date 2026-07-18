import Foundation
import LittleTidyCore
import Testing
@testable import LittleTidy

@MainActor
struct ScanReviewStorePowerReviewTests {
    @Test
    func reviewFiltersCombineScopeAndSearch() {
        let duplicate = reviewItem(title: "Invoice copy", category: .duplicate, confidence: .high, plannedURL: "/tmp/invoice-a.pdf")
        let largeFile = reviewItem(title: "Archive.zip", category: .largeFile, confidence: .medium, plannedURL: "/tmp/archive.zip")
        let store = makeStore(items: [duplicate, largeFile])

        store.reviewFilterScope = .needsReview
        store.reviewSearchText = "archive"

        let visible = store.visibleReviewItems(from: store.items)
        #expect(visible.map(\.title) == ["Archive.zip"])
    }

    @Test
    func visibleBulkSelectionSelectsOnlyHighConfidenceNonCaches() {
        let duplicate = reviewItem(title: "Duplicate", category: .duplicate, confidence: .high, plannedURL: "/tmp/duplicate")
        let largeFile = reviewItem(title: "Manual Review", category: .largeFile, confidence: .medium, plannedURL: "/tmp/manual")
        let cache = reviewItem(title: "Cache", category: .cache, confidence: .high, plannedURL: "/tmp/cache")
        let store = makeStore(items: [duplicate, largeFile, cache])

        store.selectVisibleReviewedItems(store.items)

        #expect(store.selectedItems.map(\.title) == ["Duplicate"])
        #expect(store.selectedNeedsManualReview == false)
    }

    @Test
    func undoRestoresVisibleBulkSelection() {
        let duplicate = reviewItem(title: "Duplicate", category: .duplicate, confidence: .high, plannedURL: "/tmp/duplicate")
        let store = makeStore(items: [duplicate])

        store.selectVisibleReviewedItems(store.items)
        #expect(store.selectedItems.count == 1)

        store.undoBulkSelection()
        #expect(store.selectedItems.isEmpty)
    }

    @Test
    func manualReviewRequiredForMediumSelection() {
        let item = reviewItem(title: "Questionable", category: .largeFile, confidence: .medium, plannedURL: "/tmp/questionable")
        let store = makeStore(items: [item])

        store.toggleSelection(for: item)

        #expect(store.selectedNeedsManualReview == true)
    }

    @Test
    func explicitSelectionSetterIsIdempotent() {
        let item = reviewItem(title: "Selectable", category: .largeFile, confidence: .high, plannedURL: "/tmp/selectable")
        let store = makeStore(items: [item])

        store.setSelection(for: item, isSelected: true)
        store.setSelection(for: item, isSelected: true)
        #expect(store.selectedItems.count == 1)

        store.setSelection(for: item, isSelected: false)
        store.setSelection(for: item, isSelected: false)
        #expect(store.selectedItems.isEmpty)
    }

    @Test
    func developerSelectionAllowsSupportedManualActionsOnly() {
        let store = makeStore(items: [])
        let archive = developerItem(category: .archives, activity: .unknown, mechanism: .trash, recommendation: .protected)
        let shutdownSimulator = developerItem(category: .simulatorDevices, activity: .unknown, mechanism: .simctl, recommendation: .review)
        let bootedSimulator = developerItem(category: .simulatorDevices, activity: .active, mechanism: .simctl, recommendation: .protected)
        let unknownData = developerItem(category: .xctestDevices, activity: .unknown, mechanism: .unsupported, recommendation: .unclassified)

        #expect(store.canSelectDeveloperStorageItem(archive))
        #expect(store.canSelectDeveloperStorageItem(shutdownSimulator))
        #expect(!store.canSelectDeveloperStorageItem(bootedSimulator))
        #expect(!store.canSelectDeveloperStorageItem(unknownData))

        store.setDeveloperStorageItemSelection(archive, isSelected: true)
        store.setDeveloperStorageItemSelection(archive, isSelected: true)
        #expect(store.selectedDeveloperStorageItemIDs == [archive.id])
    }

    @Test
    func relatedDataContributesOnlyWhenEnabled() {
        let relatedURL = URL(fileURLWithPath: "/tmp/Library/Application Support/demo")
        let item = reviewItem(
            title: "Fixture App",
            category: .unusedApp,
            confidence: .high,
            plannedURL: "/tmp/Fixture.app",
            bytes: 10,
            relatedData: [
                RelatedAppData(url: relatedURL, sizeBytes: 5, kind: "Application Support")
            ]
        )
        let store = makeStore(items: [item])

        store.toggleSelection(for: item)
        #expect(store.selectedBytes == 10)

        store.includeRelatedAppData = true
        #expect(store.selectedBytes == 15)
    }

    @Test
    func cleanupReportFilterReturnsMatchingStatuses() {
        let store = makeStore(items: [])
        store.cleanupReportItems = [
            CleanupReportItem(sourceURL: URL(fileURLWithPath: "/tmp/a"), destinationURL: nil, status: .failed, message: "No access", reason: "Manual", category: .largeFile, bytes: 1),
            CleanupReportItem(sourceURL: URL(fileURLWithPath: "/tmp/b"), destinationURL: URL(fileURLWithPath: "/tmp/.Trash/b"), status: .moved, message: "Moved to Trash", reason: "Duplicate", category: .duplicate, bytes: 2)
        ]

        store.cleanupReportFilter = .failed

        #expect(store.filteredCleanupReportItems().map(\.status) == [.failed])
    }

    private func reviewItem(
        title: String,
        category: CleanupCategory,
        confidence: Confidence,
        plannedURL: String,
        bytes: Int64 = 1,
        relatedData: [RelatedAppData] = []
    ) -> ReviewItem {
        let url = URL(fileURLWithPath: plannedURL)
        return ReviewItem(
            category: category,
            title: title,
            detail: "Detail",
            location: url.deletingLastPathComponent().path,
            bytes: bytes,
            confidence: confidence,
            reason: "Reason \(title)",
            plannedURLs: [url],
            contentHash: category == .duplicate ? "hash" : nil,
            bundleIdentifier: category == .unusedApp ? "com.example.fixture" : nil,
            lastOpenedDate: nil,
            installDate: nil,
            duplicateCopies: [],
            relatedData: relatedData,
            isSelected: false
        )
    }

    private func makeStore(items: [ReviewItem]) -> ScanReviewStore {
        let suiteName = "LittleTidyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ScanReviewStore(
            items: items,
            scanRoots: [URL(fileURLWithPath: "/tmp")],
            appRoots: [],
            folderBookmarkStore: FolderBookmarkStore(userDefaults: defaults),
            scanPreferencesStore: ScanPreferencesStore(userDefaults: defaults),
            cleanupHistoryStore: CleanupHistoryStore(userDefaults: defaults),
            automaticallyScanDeveloperStorage: false
        )
    }

    private func developerItem(
        category: DeveloperStorageCategory,
        activity: StorageActivityState,
        mechanism: DeveloperCleanupMechanism,
        recommendation: StorageRecommendation
    ) -> DeveloperStorageItem {
        DeveloperStorageItem(
            id: "\(category.rawValue)-\(activity.rawValue)",
            category: category,
            name: category.displayName,
            detail: "Fixture",
            url: mechanism == .trash ? URL(fileURLWithPath: "/tmp/\(category.rawValue)") : nil,
            bytes: 1,
            activity: activity,
            recoverability: mechanism == .trash ? .trashRestorable : .irreversible,
            cleanupMechanism: mechanism,
            consequence: .dataLossRisk,
            recommendation: recommendation,
            recommendationReason: "Fixture",
            externalIdentifier: mechanism == .simctl ? "DEVICE" : nil
        )
    }
}
