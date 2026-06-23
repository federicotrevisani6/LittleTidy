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
        let store = ScanReviewStore(items: [duplicate, largeFile], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])

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
        let store = ScanReviewStore(items: [duplicate, largeFile, cache], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])

        store.selectVisibleReviewedItems(store.items)

        #expect(store.selectedItems.map(\.title) == ["Duplicate"])
        #expect(store.selectedNeedsManualReview == false)
    }

    @Test
    func undoRestoresVisibleBulkSelection() {
        let duplicate = reviewItem(title: "Duplicate", category: .duplicate, confidence: .high, plannedURL: "/tmp/duplicate")
        let store = ScanReviewStore(items: [duplicate], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])

        store.selectVisibleReviewedItems(store.items)
        #expect(store.selectedItems.count == 1)

        store.undoBulkSelection()
        #expect(store.selectedItems.isEmpty)
    }

    @Test
    func manualReviewRequiredForMediumSelection() {
        let item = reviewItem(title: "Questionable", category: .largeFile, confidence: .medium, plannedURL: "/tmp/questionable")
        let store = ScanReviewStore(items: [item], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])

        store.toggleSelection(for: item)

        #expect(store.selectedNeedsManualReview == true)
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
        let store = ScanReviewStore(items: [item], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])

        store.toggleSelection(for: item)
        #expect(store.selectedBytes == 10)

        store.includeRelatedAppData = true
        #expect(store.selectedBytes == 15)
    }

    @Test
    func cleanupReportFilterReturnsMatchingStatuses() {
        let store = ScanReviewStore(items: [], scanRoots: [URL(fileURLWithPath: "/tmp")], appRoots: [])
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
}
