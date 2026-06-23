import Foundation
import LittleTidyCore
import AppKit

@MainActor
final class ScanReviewStore: ObservableObject {
    @Published var selectedSection: SidebarSection = .overview
    @Published var isScanning = false
    @Published var hasCompletedScan = false
    @Published var scanDidFail = false
    @Published var progress: Double = 0
    @Published var scanPhase = "Ready"
    @Published var currentScanLocation: String?
    @Published var currentRootIndex = 0
    @Published var rootCount = 0
    @Published var scannedFiles = 0
    @Published var scannedBytes: Int64 = 0
    @Published var skippedItems = 0
    @Published var permissionErrors = 0
    @Published var scanIssues: [ScanIssue] = []
    @Published var statusMessage = "Ready"
    @Published var permissionReadinessItems: [PermissionReadinessItem] = []
    @Published var scanRoots: [URL] {
        didSet { refreshPermissionReadiness() }
    }
    @Published var appRoots: [URL] {
        didSet { refreshPermissionReadiness() }
    }
    @Published var includeHiddenFiles = false {
        didSet { persistScanPreferences() }
    }
    @Published var includeSystemFolders = false {
        didSet {
            persistScanPreferences()
            refreshPermissionReadiness()
        }
    }
    @Published var includeCaches = true {
        didSet { persistScanPreferences() }
    }
    @Published var includeRelatedAppData = false {
        didSet {
            persistScanPreferences()
            cleanupResultMessage = nil
            cleanupReportItems = []
        }
    }
    @Published var minimumDuplicateSize: Int64 = 1_000_000 {
        didSet { persistScanPreferences() }
    }
    @Published var largeFileThreshold: Int64 = 500_000_000 {
        didSet { persistScanPreferences() }
    }
    @Published var items: [ReviewItem]
    @Published var folderUsage: [FolderUsage] = []
    @Published var cleanupErrorMessage: String?
    @Published var cleanupResultMessage: String?
    @Published var cleanupReportItems: [CleanupReportItem] = []
    @Published var cleanupHistory: [CleanupHistoryEntry] = []
    @Published var isCleaning = false
    @Published var reviewSortOption: ReviewSortOption = .largestFirst
    @Published var reviewSearchText = ""
    @Published var reviewFilterScope: ReviewFilterScope = .all
    @Published var selectedInspectorItemID: ReviewItem.ID?
    @Published var cleanupReportFilter: CleanupReportFilter = .all
    @Published var manualReviewConfirmed = false
    @Published var bulkSelectionUndoMessage: String?

    private var scanTask: Task<Void, Never>?
    private var analysisTask: Task<CleanupAnalysisResult, Error>?
    private var previousSelectionSnapshot: [SelectionSnapshot]?
    private let trashPlanBuilder: TrashPlanBuilder
    private let trashExecutor: TrashExecutor
    private let folderBookmarkStore: FolderBookmarkStore
    private let scanPreferencesStore: ScanPreferencesStore
    private let cleanupHistoryStore: CleanupHistoryStore

    init(
        items: [ReviewItem] = [],
        scanRoots: [URL]? = nil,
        appRoots: [URL]? = nil,
        folderBookmarkStore: FolderBookmarkStore = .shared,
        scanPreferencesStore: ScanPreferencesStore = .shared,
        cleanupHistoryStore: CleanupHistoryStore = .shared,
        trashPlanBuilder: TrashPlanBuilder = TrashPlanBuilder(),
        trashExecutor: TrashExecutor = TrashExecutor()
    ) {
        self.items = items
        self.folderBookmarkStore = folderBookmarkStore
        self.scanPreferencesStore = scanPreferencesStore
        self.cleanupHistoryStore = cleanupHistoryStore
        if ProcessInfo.processInfo.environment["LITTLE_TIDY_FIXTURE_ROOT"] != nil {
            let fixture = Self.qaFixtureRoot()
            self.scanRoots = scanRoots ?? [fixture]
            self.appRoots = appRoots ?? [fixture.appendingPathComponent("Applications", isDirectory: true)]
        } else {
            self.scanRoots = scanRoots ?? folderBookmarkStore.restoredScanRoots(fallback: Self.defaultScanRoots())
            self.appRoots = appRoots ?? folderBookmarkStore.restoredAppRoots(fallback: Self.defaultApplicationRoots())
        }
        self.trashPlanBuilder = trashPlanBuilder
        self.trashExecutor = trashExecutor

        let preferences = scanPreferencesStore.load()
        self.includeHiddenFiles = preferences.includeHiddenFiles
        self.includeSystemFolders = preferences.includeSystemFolders
        self.includeCaches = preferences.includeCaches
        self.includeRelatedAppData = preferences.includeRelatedAppData
        self.minimumDuplicateSize = preferences.minimumDuplicateSize
        self.largeFileThreshold = preferences.largeFileThreshold
        self.cleanupHistory = cleanupHistoryStore.load()
        refreshPermissionReadiness()
    }

    deinit {
        scanTask?.cancel()
        analysisTask?.cancel()
    }

    var selectedItems: [ReviewItem] {
        items.filter { isItemSelected($0) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + selectedBytesForItem($1) }
    }

    var selectedFilesystemEntryCount: Int {
        selectedItems.reduce(0) { $0 + selectedPlannedURLs(for: $1).count }
    }

    var selectedNeedsManualReview: Bool {
        selectedItems.contains { $0.confidence != .high }
    }

    var selectedRiskBreakdown: [(ReviewRisk, Int, Int64)] {
        ReviewRisk.allCases.compactMap { risk in
            let matchingItems = selectedItems.filter { ReviewRisk.risk(for: $0.confidence) == risk }
            guard !matchingItems.isEmpty else { return nil }
            let bytes = matchingItems.reduce(Int64(0)) { $0 + selectedBytesForItem($1) }
            return (risk, matchingItems.count, bytes)
        }
    }

    var selectedCategoryBreakdown: [(CleanupCategory, Int, Int64)] {
        Self.cleanupCategoryOrder.compactMap { category in
            let categoryItems = selectedItems.filter { $0.category == category }
            guard !categoryItems.isEmpty else { return nil }
            return (category, categoryItems.count, selectedBytes(for: category))
        }
    }

    func selectedBytes(for category: CleanupCategory) -> Int64 {
        selectedItems
            .filter { $0.category == category }
            .reduce(0) { $0 + selectedBytesForItem($1) }
    }

    func selectedCount(for category: CleanupCategory) -> Int {
        selectedItems.filter { $0.category == category }.count
    }

    func selectedEntryCount(for item: ReviewItem) -> Int {
        selectedPlannedURLs(for: item).count
    }

    func selectedBytes(for item: ReviewItem) -> Int64 {
        selectedBytesForItem(item)
    }

    func plannedURLs(for item: ReviewItem) -> [URL] {
        if item.duplicateCopies.isEmpty {
            return item.plannedURLs + includedRelatedURLs(for: item)
        }
        return item.duplicateCopies
            .filter { !$0.isRecommendedKeep }
            .map(\.url)
    }

    func visibleReviewItems(from items: [ReviewItem]) -> [ReviewItem] {
        items.filter { item in
            matchesReviewScope(item) && matchesReviewSearch(item)
        }
    }

    func visibleSelectedBytes(from items: [ReviewItem]) -> Int64 {
        visibleReviewItems(from: items).reduce(Int64(0)) { total, item in
            total + selectedBytesForItem(item)
        }
    }

    func visibleSelectedCount(from items: [ReviewItem]) -> Int {
        visibleReviewItems(from: items).filter(isItemSelected).count
    }

    var cleanupPlanValidation: CleanupPlanValidation {
        if isScanning {
            return CleanupPlanValidation(
                state: .blocked,
                title: "Scan in progress",
                detail: "Wait for the current scan to finish before building a cleanup plan.",
                warnings: []
            )
        }

        if isCleaning {
            return CleanupPlanValidation(
                state: .blocked,
                title: "Cleanup in progress",
                detail: "Wait for the current cleanup operation to finish.",
                warnings: []
            )
        }

        guard !selectedItems.isEmpty else {
            return CleanupPlanValidation(
                state: .noSelection,
                title: "No items selected",
                detail: "Select duplicates, large files, or unused apps to build a cleanup plan.",
                warnings: []
            )
        }

        do {
            let plan = try buildCleanupPlan()
            return CleanupPlanValidation(
                state: .ready,
                title: "Plan ready",
                detail: "\(plan.items.count) filesystem entries can be moved to Trash.",
                warnings: cleanupPlanWarnings()
            )
        } catch {
            return CleanupPlanValidation(
                state: .blocked,
                title: "Plan blocked",
                detail: Self.describe(error),
                warnings: cleanupPlanWarnings()
            )
        }
    }

    var hasPermissionWarnings: Bool {
        permissionReadinessItems.contains { $0.severity == .warning }
    }

    func items(for category: CleanupCategory) -> [ReviewItem] {
        sortedItems(items.filter { $0.category == category })
    }

    func reclaimableBytes(for category: CleanupCategory) -> Int64 {
        items(for: category).reduce(0) { $0 + reclaimableBytes(for: $1) }
    }

    var suggestedSelectionPreview: BulkSelectionPreview {
        bulkSelectionPreview(for: .suggestedWithoutCaches)
    }

    var reviewedCachesSelectionPreview: BulkSelectionPreview {
        bulkSelectionPreview(for: .reviewedCaches)
    }

    func toggleSelection(for item: ReviewItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        if items[index].duplicateCopies.isEmpty {
            items[index].isSelected.toggle()
        } else {
            let shouldSelect = !items[index].duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
            for copyIndex in items[index].duplicateCopies.indices {
                if !items[index].duplicateCopies[copyIndex].isRecommendedKeep {
                    items[index].duplicateCopies[copyIndex].isSelected = shouldSelect
                }
            }
            items[index].isSelected = shouldSelect
        }
        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        manualReviewConfirmed = false
        bulkSelectionUndoMessage = nil
    }

    func toggleDuplicateCopy(for item: ReviewItem, copy: DuplicateCopyReview) {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }),
              let copyIndex = items[itemIndex].duplicateCopies.firstIndex(where: { $0.id == copy.id }),
              !items[itemIndex].duplicateCopies[copyIndex].isRecommendedKeep else {
            return
        }

        items[itemIndex].duplicateCopies[copyIndex].isSelected.toggle()
        items[itemIndex].isSelected = items[itemIndex].duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        manualReviewConfirmed = false
        bulkSelectionUndoMessage = nil
    }

    func selectSuggested() {
        applyBulkSelection(.suggestedWithoutCaches)
    }

    func applyBulkSelection(_ mode: BulkSelectionMode) {
        previousSelectionSnapshot = items.map(SelectionSnapshot.init(item:))
        for index in items.indices {
            let shouldSelect = shouldSelectItem(items[index], for: mode)

            if !items[index].duplicateCopies.isEmpty {
                for copyIndex in items[index].duplicateCopies.indices {
                    items[index].duplicateCopies[copyIndex].isSelected = shouldSelect && !items[index].duplicateCopies[copyIndex].isRecommendedKeep
                }
                items[index].isSelected = items[index].duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
            } else if mode == .reviewedCaches {
                if items[index].category == .cache {
                    items[index].isSelected = shouldSelect
                }
            } else {
                items[index].isSelected = shouldSelect
            }
        }
        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        manualReviewConfirmed = false
        let preview = bulkSelectionPreview(for: mode)
        bulkSelectionUndoMessage = "\(preview.itemCount) items selected"
    }

    func selectHighConfidence(in visibleItems: [ReviewItem]) {
        applyVisibleSelection(visibleItems, shouldSelect: { item in
            item.confidence == .high && item.category != .cache
        }, messagePrefix: "High-confidence")
    }

    func selectVisibleReviewedItems(_ visibleItems: [ReviewItem], includeCaches: Bool = false) {
        applyVisibleSelection(visibleItems, shouldSelect: { item in
            item.confidence == .high && (includeCaches || item.category != .cache)
        }, messagePrefix: "Visible")
    }

    func deselectVisibleItems(_ visibleItems: [ReviewItem]) {
        applyVisibleSelection(visibleItems, shouldSelect: { _ in false }, messagePrefix: "Visible", isDeselecting: true)
    }

    func filteredCleanupReportItems() -> [CleanupReportItem] {
        cleanupReportItems.filter { item in
            switch cleanupReportFilter {
            case .all:
                return true
            case .moved:
                return item.status == .moved
            case .skipped:
                return item.status == .skipped
            case .failed:
                return item.status == .failed
            }
        }
    }

    func undoBulkSelection() {
        guard let snapshot = previousSelectionSnapshot else {
            return
        }

        for index in items.indices {
            guard let saved = snapshot.first(where: { $0.itemID == items[index].id }) else {
                continue
            }
            items[index].isSelected = saved.isSelected
            for copyIndex in items[index].duplicateCopies.indices {
                let copyID = items[index].duplicateCopies[copyIndex].id
                if let wasSelected = saved.duplicateCopySelections[copyID] {
                    items[index].duplicateCopies[copyIndex].isSelected = wasSelected
                }
            }
        }

        previousSelectionSnapshot = nil
        bulkSelectionUndoMessage = nil
        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        manualReviewConfirmed = false
    }

#if DEBUG
    func useFixtureSettings() {
        let fixture = Self.qaFixtureRoot()
        scanRoots = [fixture]
        appRoots = [fixture.appendingPathComponent("Applications", isDirectory: true)]
        persistApprovedFolders()
        minimumDuplicateSize = 1_000_000
        largeFileThreshold = 1_000_000
        includeHiddenFiles = false
        includeSystemFolders = false
        statusMessage = "Fixture QA settings loaded"
    }
#endif

    func resetScanSettings() {
        scanRoots = Self.defaultScanRoots()
        appRoots = Self.defaultApplicationRoots()
        folderBookmarkStore.clear()
        scanPreferencesStore.reset()
        minimumDuplicateSize = 1_000_000
        largeFileThreshold = 500_000_000
        includeHiddenFiles = false
        includeSystemFolders = false
        includeCaches = true
        includeRelatedAppData = false
        statusMessage = "Default scan settings restored"
    }

    func revealInFinder(_ item: ReviewItem) {
        guard let url = selectedPlannedURLs(for: item).first ?? item.plannedURLs.first ?? item.duplicateCopies.first?.url else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFirstPlannedURL(_ item: ReviewItem) {
        guard let url = selectedPlannedURLs(for: item).first ?? item.plannedURLs.first ?? item.duplicateCopies.first?.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func preview(_ item: ReviewItem) {
        let urls = selectedPlannedURLs(for: item) + item.plannedURLs + item.duplicateCopies.map(\.url)
        QuickLookPreviewController.shared.preview(Self.uniqueExistingURLs(urls))
    }

    func revealInFinder(_ copy: DuplicateCopyReview) {
        NSWorkspace.shared.activateFileViewerSelecting([copy.url])
    }

    func revealInFinder(forURL url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ copy: DuplicateCopyReview) {
        NSWorkspace.shared.open(copy.url)
    }

    func preview(_ copy: DuplicateCopyReview) {
        QuickLookPreviewController.shared.preview([copy.url])
    }

    func validateCleanupPlan() -> TrashPlan? {
        do {
            let plan = try buildCleanupPlan()
            cleanupErrorMessage = nil
            return plan
        } catch {
            cleanupErrorMessage = Self.describe(error)
            return nil
        }
    }

    func executeCleanup() {
        guard let plan = validateCleanupPlan() else {
            return
        }

        execute(plan: plan)
    }

    func retryFailedCleanup() {
        let failedItems = cleanupReportItems.filter { $0.status == .failed }
        guard !failedItems.isEmpty else {
            return
        }

        let plan = TrashPlan(items: failedItems.map { item in
            TrashPlanItem(
                sourceURL: item.sourceURL,
                bytes: item.bytes,
                category: item.category ?? .largeFile,
                reason: item.reason
            )
        })
        execute(plan: plan, preservingReport: true)
    }

    func openTrash() {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trashURL)
    }

    private func execute(plan: TrashPlan, preservingReport: Bool = false) {
        let existingReportItems = preservingReport ? cleanupReportItems : []
        isCleaning = true
        cleanupResultMessage = nil
        if !preservingReport {
            cleanupReportItems = []
        }

        Task { [weak self] in
            guard let self else { return }
            let trashExecutor = self.trashExecutor
            let scopedAccess = SecurityScopedFolderAccess(urls: self.approvedCleanupRoots())
            let result = await Task.detached(priority: .userInitiated) {
                _ = scopedAccess
                return trashExecutor.execute(plan)
            }.value

            let trashedSourcePaths = Set(result.trashed.map { $0.sourceURL.standardizedFileURL.path })
            let newReportItems = self.cleanupReportItems(from: result, plan: plan)
            self.cleanupReportItems = existingReportItems + newReportItems
            self.items = self.items.compactMap { self.itemAfterCleanup($0, trashedSourcePaths: trashedSourcePaths) }
            self.isCleaning = false
            self.cleanupErrorMessage = result.failed.isEmpty ? nil : "\(result.failed.count) items could not be moved to Trash."
            self.cleanupResultMessage = preservingReport ? "Retry complete: \(result.trashed.count) moved to Trash, \(result.skipped.count) skipped." : "\(result.trashed.count) moved to Trash, \(result.skipped.count) skipped."
            self.statusMessage = preservingReport ? "Cleanup retry complete" : "Cleanup complete"
            self.manualReviewConfirmed = false
            self.recordCleanupHistory(from: newReportItems)
            self.selectedSection = .cleanupPlan
        }
    }

    func clearCleanupHistory() {
        cleanupHistoryStore.clear()
        cleanupHistory = []
    }

    private func recordCleanupHistory(from reportItems: [CleanupReportItem]) {
        let moved = reportItems.filter { $0.status == .moved }
        guard !moved.isEmpty else {
            return
        }

        var bytesByCategory: [String: Int64] = [:]
        for item in moved {
            let key = (item.category ?? .largeFile).rawValue
            bytesByCategory[key, default: 0] += item.bytes
        }

        let entry = CleanupHistoryEntry(
            bytesFreed: moved.reduce(Int64(0)) { $0 + $1.bytes },
            movedCount: moved.count,
            skippedCount: reportItems.filter { $0.status == .skipped }.count,
            failedCount: reportItems.filter { $0.status == .failed }.count,
            bytesByCategory: bytesByCategory
        )
        cleanupHistory = cleanupHistoryStore.record(entry)
    }

    private func buildCleanupPlan() throws -> TrashPlan {
        let planItems = selectedItems.flatMap { item in
            let plannedURLs = selectedPlannedURLs(for: item)
            return plannedURLs.map { url in
                TrashPlanItem(
                    sourceURL: url,
                    bytes: bytes(for: url, in: item),
                    category: item.category,
                    reason: item.reason
                )
            }
        }

        return try trashPlanBuilder.buildPlan(
            items: planItems,
            approvedRoots: approvedCleanupRoots()
        )
    }

    private func approvedCleanupRoots() -> [URL] {
        // Cache candidates live in well-known locations outside the user-selected
        // scan roots (e.g. ~/Library/Caches), so approve their parent directories
        // to satisfy the trash plan's containment check.
        let cacheRoots = items
            .filter { $0.category == .cache }
            .flatMap { $0.plannedURLs }
            .map { $0.deletingLastPathComponent() }

        // Related app data lives in standard Library locations outside the scan
        // roots; approve their parents so the containment check passes.
        let relatedDataRoots = items
            .filter { $0.category == .unusedApp }
            .flatMap { $0.relatedData }
            .map { $0.url.deletingLastPathComponent() }

        return Array(
            Dictionary(
                grouping: scanRoots + appRoots + cacheRoots + relatedDataRoots,
                by: { $0.standardizedFileURL.path }
            )
            .compactMap { $0.value.first }
        )
    }

    private func isItemSelected(_ item: ReviewItem) -> Bool {
        if item.duplicateCopies.isEmpty {
            return item.isSelected
        }
        return item.duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
    }

    private func applyVisibleSelection(
        _ visibleItems: [ReviewItem],
        shouldSelect: (ReviewItem) -> Bool,
        messagePrefix: String,
        isDeselecting: Bool = false
    ) {
        let visibleIDs = Set(visibleItems.map(\.id))
        guard !visibleIDs.isEmpty else {
            return
        }

        previousSelectionSnapshot = items.map(SelectionSnapshot.init(item:))
        var changedCount = 0

        for index in items.indices where visibleIDs.contains(items[index].id) {
            let newSelection = shouldSelect(items[index])
            let oldSelection = isItemSelected(items[index])

            if !items[index].duplicateCopies.isEmpty {
                for copyIndex in items[index].duplicateCopies.indices {
                    items[index].duplicateCopies[copyIndex].isSelected = newSelection && !items[index].duplicateCopies[copyIndex].isRecommendedKeep
                }
                items[index].isSelected = items[index].duplicateCopies.contains { $0.isSelected && !$0.isRecommendedKeep }
            } else {
                items[index].isSelected = newSelection
            }

            if oldSelection != isItemSelected(items[index]) {
                changedCount += 1
            }
        }

        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        manualReviewConfirmed = false
        bulkSelectionUndoMessage = isDeselecting ? "\(changedCount) visible items deselected" : "\(messagePrefix) items selected: \(changedCount)"
    }

    private func matchesReviewScope(_ item: ReviewItem) -> Bool {
        switch reviewFilterScope {
        case .all:
            return true
        case .selected:
            return isItemSelected(item)
        case .unselected:
            return !isItemSelected(item)
        case .highConfidence:
            return item.confidence == .high
        case .needsReview:
            return item.confidence != .high
        case .includesRelatedData:
            return !item.relatedData.isEmpty
        case .failedLastCleanup:
            return failedCleanupSourcePaths.contains { path in
                allCandidateURLs(for: item).contains { $0.standardizedFileURL.path == path }
            }
        }
    }

    private func matchesReviewSearch(_ item: ReviewItem) -> Bool {
        let query = reviewSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        let searchableValues = [
            item.title,
            item.detail,
            item.location,
            item.reason,
            item.category.displayTitle,
            item.confidence.rawValue
        ] + allCandidateURLs(for: item).map(\.path) + item.relatedData.flatMap { [$0.kind, $0.url.lastPathComponent, $0.url.path] }

        return searchableValues.contains { value in
            value.localizedCaseInsensitiveContains(query)
        }
    }

    private var failedCleanupSourcePaths: Set<String> {
        Set(cleanupReportItems.filter { $0.status == .failed }.map { $0.sourceURL.standardizedFileURL.path })
    }

    private func allCandidateURLs(for item: ReviewItem) -> [URL] {
        item.plannedURLs + item.duplicateCopies.map(\.url) + item.relatedData.map(\.url)
    }

    private func selectedPlannedURLs(for item: ReviewItem) -> [URL] {
        if item.duplicateCopies.isEmpty {
            guard item.isSelected else {
                return []
            }
            return item.plannedURLs + includedRelatedURLs(for: item)
        }
        return item.duplicateCopies
            .filter { $0.isSelected && !$0.isRecommendedKeep }
            .map(\.url)
    }

    private func selectedBytesForItem(_ item: ReviewItem) -> Int64 {
        if item.duplicateCopies.isEmpty {
            return item.isSelected ? item.bytes + includedRelatedBytes(for: item) : 0
        }
        return item.duplicateCopies
            .filter { $0.isSelected && !$0.isRecommendedKeep }
            .reduce(Int64(0)) { $0 + $1.bytes }
    }

    private func reclaimableBytes(for item: ReviewItem) -> Int64 {
        if item.duplicateCopies.isEmpty {
            return item.bytes + includedRelatedBytes(for: item)
        }
        return item.duplicateCopies
            .filter { !$0.isRecommendedKeep }
            .reduce(Int64(0)) { $0 + $1.bytes }
    }

    private func bulkSelectionPreview(for mode: BulkSelectionMode) -> BulkSelectionPreview {
        let selectedCandidates = items.filter { shouldSelectItem($0, for: mode) }
        let breakdown = Self.cleanupCategoryOrder.compactMap { category -> BulkSelectionPreview.CategoryBreakdown? in
            let categoryItems = selectedCandidates.filter { $0.category == category }
            guard !categoryItems.isEmpty else { return nil }
            return BulkSelectionPreview.CategoryBreakdown(
                category: category,
                itemCount: categoryItems.count,
                filesystemEntryCount: categoryItems.reduce(0) { $0 + bulkFilesystemEntryCount(for: $1) },
                bytes: categoryItems.reduce(Int64(0)) { $0 + bulkBytes(for: $1) }
            )
        }

        let excludedCaches = mode == .suggestedWithoutCaches ? items.filter { $0.category == .cache && $0.confidence == .high } : []

        return BulkSelectionPreview(
            mode: mode,
            itemCount: selectedCandidates.count,
            filesystemEntryCount: selectedCandidates.reduce(0) { $0 + bulkFilesystemEntryCount(for: $1) },
            bytes: selectedCandidates.reduce(Int64(0)) { $0 + bulkBytes(for: $1) },
            categoryBreakdown: breakdown,
            excludedCacheItemCount: excludedCaches.count,
            excludedCacheBytes: excludedCaches.reduce(Int64(0)) { $0 + bulkBytes(for: $1) }
        )
    }

    private func shouldSelectItem(_ item: ReviewItem, for mode: BulkSelectionMode) -> Bool {
        guard item.confidence == .high else {
            return false
        }

        switch mode {
        case .suggestedWithoutCaches:
            return item.category != .cache
        case .reviewedCaches:
            return item.category == .cache
        }
    }

    private func bulkFilesystemEntryCount(for item: ReviewItem) -> Int {
        if item.duplicateCopies.isEmpty {
            return max(1, item.plannedURLs.count)
        }
        return item.duplicateCopies.filter { !$0.isRecommendedKeep }.count
    }

    private func bulkBytes(for item: ReviewItem) -> Int64 {
        if item.duplicateCopies.isEmpty {
            return item.bytes
        }
        return item.duplicateCopies
            .filter { !$0.isRecommendedKeep }
            .reduce(Int64(0)) { $0 + $1.bytes }
    }

    private static let cleanupCategoryOrder: [CleanupCategory] = [.duplicate, .largeFile, .unusedApp, .cache]

    /// Related app-data entries that should join the cleanup plan, gated by the
    /// opt-in "deep uninstall" toggle and applicable only to unused apps.
    private func includedRelatedURLs(for item: ReviewItem) -> [URL] {
        guard includeRelatedAppData, item.category == .unusedApp else {
            return []
        }
        return item.relatedData.map(\.url)
    }

    private func includedRelatedBytes(for item: ReviewItem) -> Int64 {
        guard includeRelatedAppData, item.category == .unusedApp else {
            return 0
        }
        return item.relatedData.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private func bytes(for url: URL, in item: ReviewItem) -> Int64 {
        if let copy = item.duplicateCopies.first(where: { $0.url == url }) {
            return copy.bytes
        }
        if let related = item.relatedData.first(where: { $0.url == url }) {
            return related.sizeBytes
        }
        // The item's own size applies to its primary planned entry (e.g. an app
        // bundle, a large file). A single-entry item always uses it directly.
        if item.plannedURLs.contains(url) || (item.plannedURLs.count <= 1 && item.relatedData.isEmpty) {
            return item.bytes
        }
        // Anything else: measure the entry rather than splitting a total evenly.
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]),
           let measured = values.totalFileAllocatedSize ?? values.fileSize {
            return Int64(measured)
        }
        return 0
    }

    private func itemAfterCleanup(_ item: ReviewItem, trashedSourcePaths: Set<String>) -> ReviewItem? {
        if item.duplicateCopies.isEmpty {
            let plannedURLs = selectedPlannedURLs(for: item)
            return plannedURLs.contains { trashedSourcePaths.contains($0.standardizedFileURL.path) } ? nil : item
        }

        var updatedItem = item
        updatedItem.duplicateCopies.removeAll { copy in
            trashedSourcePaths.contains(copy.url.standardizedFileURL.path)
        }
        for copyIndex in updatedItem.duplicateCopies.indices {
            updatedItem.duplicateCopies[copyIndex].isSelected = false
        }
        updatedItem.isSelected = false

        let removableCopies = updatedItem.duplicateCopies.filter { !$0.isRecommendedKeep }
        return removableCopies.isEmpty ? nil : updatedItem
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Use Folders"
        panel.message = "Choose folders to scan for duplicates and large files."

        guard panel.runModal() == .OK else {
            return
        }

        let merged = scanRoots + panel.urls
        scanRoots = Array(Dictionary(grouping: merged, by: { $0.standardizedFileURL.path }).compactMap { $0.value.first })
        folderBookmarkStore.saveScanRoots(scanRoots)
        statusMessage = "\(scanRoots.count) folders selected"
    }

    func chooseAppFolders() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Use App Folders"
        panel.message = "Choose folders that contain .app bundles."

        guard panel.runModal() == .OK else {
            return
        }

        let merged = appRoots + panel.urls
        appRoots = Array(Dictionary(grouping: merged, by: { $0.standardizedFileURL.path }).compactMap { $0.value.first })
        folderBookmarkStore.saveAppRoots(appRoots)
        statusMessage = "\(appRoots.count) app folders selected"
    }

    func openFullDiskAccessSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for string in settingsURLs {
            guard let url = URL(string: string) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func startOrCancelScan() {
        if isScanning {
            scanTask?.cancel()
            scanTask = nil
            analysisTask?.cancel()
            analysisTask = nil
            isScanning = false
            progress = 0
            scanPhase = "Cancelled"
            currentScanLocation = nil
            statusMessage = "Scan cancelled"
            return
        }

        startScan()
    }

    private func startScan() {
        let roots = scanRoots
        let appRoots = appRoots
        let options = ScanOptions(
            includeHiddenFiles: includeHiddenFiles,
            includeSystemFolders: includeSystemFolders,
            includeCaches: includeCaches,
            minimumDuplicateSize: minimumDuplicateSize,
            largeFileThreshold: largeFileThreshold
        )

        items = []
        folderUsage = []
        cleanupErrorMessage = nil
        cleanupResultMessage = nil
        cleanupReportItems = []
        scannedFiles = 0
        scannedBytes = 0
        skippedItems = 0
        permissionErrors = 0
        scanIssues = []
        progress = 0
        scanPhase = "Preparing"
        currentScanLocation = nil
        currentRootIndex = 0
        rootCount = roots.count
        isScanning = true
        scanDidFail = false
        statusMessage = "Scanning approved folders"
        selectedSection = .overview

        scanTask = Task { [weak self] in
            guard let self else { return }
            let scanner = FileInventoryScanner()
            let scopedAccess = SecurityScopedFolderAccess(urls: roots + appRoots)
            var records: [FileRecord] = []

            do {
                _ = scopedAccess
                for try await event in scanner.scan(request: ScanRequest(roots: roots, options: options)) {
                    try Task.checkCancellation()

                    switch event {
                    case .started:
                        self.scanPhase = "Indexing files"
                        self.statusMessage = "Indexing files"
                    case .rootStarted(let url, let index, let total):
                        self.scanPhase = "Indexing files"
                        self.currentScanLocation = url.path(percentEncoded: false)
                        self.currentRootIndex = index
                        self.rootCount = total
                        // Indeterminate during indexing: the true total file count
                        // is unknown, so root position is shown as text ("X of Y")
                        // rather than as a misleading determinate bar.
                        self.progress = 0
                    case .indexedFile(let record):
                        records.append(record)
                    case .skipped(let url, let reason):
                        self.skippedItems += 1
                        self.recordScanIssue(kind: .skipped, url: url, message: reason)
                    case .permissionDenied(let url, let error):
                        self.permissionErrors += 1
                        self.recordScanIssue(kind: .permissionDenied, url: url, message: error.localizedDescription)
                    case .progress(let progress):
                        self.applyScanProgress(progress)
                    case .completed(let summary):
                        self.scannedFiles = summary.scannedFiles
                        self.scannedBytes = summary.scannedBytes
                        self.skippedItems = summary.skippedItems
                        self.permissionErrors = summary.permissionErrors
                        self.scanPhase = "Analyzing results"
                        self.currentScanLocation = nil
                        self.progress = 0.9
                        self.statusMessage = "Analyzing files"
                        self.refreshPermissionReadiness()
                    }
                }

                let analysisTask = Task.detached(priority: .userInitiated) {
                    try CleanupAnalysis().analyze(files: records, options: options, appRoots: appRoots, scanRoots: roots)
                }
                self.analysisTask = analysisTask
                let result = try await analysisTask.value
                self.analysisTask = nil

                self.items = Self.reviewItems(from: result)
                self.folderUsage = result.folderUsage
                self.progress = 1
                self.scanPhase = "Complete"
                self.currentScanLocation = nil
                self.isScanning = false
                self.hasCompletedScan = true
                self.scanDidFail = false
                self.statusMessage = "Scan complete"
                self.applyVisualQASectionIfNeeded()
            } catch is CancellationError {
                self.progress = 0
                self.scanPhase = "Cancelled"
                self.currentScanLocation = nil
                self.isScanning = false
                self.statusMessage = "Scan cancelled"
            } catch {
                self.progress = 0
                self.scanPhase = "Failed"
                self.currentScanLocation = nil
                self.isScanning = false
                self.scanDidFail = true
                self.statusMessage = "Scan failed: \(error.localizedDescription)"
                self.refreshPermissionReadiness()
            }
        }
    }

    private func applyScanProgress(_ snapshot: ScanProgress) {
        scannedFiles = snapshot.scannedFiles
        scannedBytes = snapshot.scannedBytes
        skippedItems = snapshot.skippedItems
        permissionErrors = snapshot.permissionErrors
        currentRootIndex = snapshot.rootIndex
        rootCount = snapshot.rootCount
        currentScanLocation = snapshot.currentRoot?.path(percentEncoded: false)
        // Stay indeterminate while indexing; the determinate tail begins at the
        // analysis phase (.completed sets 0.9, the final result sets 1).
        progress = 0
    }

    private func cleanupPlanWarnings() -> [String] {
        var warnings: [String] = []

        if selectedItems.contains(where: { !$0.duplicateCopies.isEmpty }) {
            warnings.append("Duplicate groups keep at least one copy; recommended keep copies are not selected.")
        }

        if selectedItems.contains(where: { $0.category == .unusedApp }) {
            if includeRelatedAppData {
                warnings.append("Deep uninstall is on: related app data matched by bundle identifier will also be moved to Trash.")
            } else {
                warnings.append("Unused app cleanup moves only the app bundle; related app data is excluded.")
            }
        }

        if selectedItems.contains(where: { $0.category == .cache }) {
            warnings.append("Caches are regenerable, but review cache-heavy selections before moving them to Trash.")
        }

        let missingCount = selectedItems
            .flatMap { selectedPlannedURLs(for: $0) }
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .count

        if missingCount > 0 {
            warnings.append("\(missingCount) selected entries are already missing and will be skipped.")
        }

        return warnings
    }

    func refreshPermissionReadiness() {
        var items: [PermissionReadinessItem] = []
        var rootIssues = rootReadinessIssues(for: scanRoots, label: "File root")
        rootIssues += rootReadinessIssues(for: appRoots, label: "App root")

        if scanRoots.isEmpty {
            rootIssues.append(PermissionReadinessItem(
                title: "No file folders selected",
                detail: "Choose at least one folder before scanning for duplicates and large files.",
                severity: .warning,
                url: nil
            ))
        }

        if rootIssues.isEmpty {
            items.append(PermissionReadinessItem(
                title: "Selected folders accessible",
                detail: "\(scanRoots.count) file roots and \(appRoots.count) app roots are ready to scan.",
                severity: .ready,
                url: nil
            ))
        } else {
            items.append(contentsOf: rootIssues.prefix(6))
        }

        if includeSystemFolders || permissionErrors > 0 {
            items.append(PermissionReadinessItem(
                title: "Full Disk Access recommended",
                detail: "Protected locations may remain unavailable until LittleTidy is allowed in Privacy & Security.",
                severity: .warning,
                url: nil
            ))
        } else {
            items.append(PermissionReadinessItem(
                title: "Full Disk Access optional",
                detail: "Folder-based scans work with selected folders. Grant Full Disk Access later for broader protected locations.",
                severity: .advisory,
                url: nil
            ))
        }

        permissionReadinessItems = items
    }

    private func rootReadinessIssues(for roots: [URL], label: String) -> [PermissionReadinessItem] {
        roots.compactMap { root in
            if !includeSystemFolders, Self.isSystemRoot(root) {
                return PermissionReadinessItem(
                    title: "\(label) blocked by settings",
                    detail: "\(root.path(percentEncoded: false)) is a system location. Enable system folders only when you intend to scan it.",
                    severity: .warning,
                    url: root
                )
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                return PermissionReadinessItem(
                    title: "\(label) missing",
                    detail: root.path(percentEncoded: false),
                    severity: .warning,
                    url: root
                )
            }

            guard isDirectory.boolValue else {
                return PermissionReadinessItem(
                    title: "\(label) is not a folder",
                    detail: root.path(percentEncoded: false),
                    severity: .warning,
                    url: root
                )
            }

            guard FileManager.default.isReadableFile(atPath: root.path) else {
                return PermissionReadinessItem(
                    title: "\(label) not readable",
                    detail: "\(root.path(percentEncoded: false)) may need folder permission or Full Disk Access.",
                    severity: .warning,
                    url: root
                )
            }

            return nil
        }
    }

    private func recordScanIssue(kind: ScanIssue.Kind, url: URL, message: String) {
        guard scanIssues.count < 100 else {
            return
        }
        scanIssues.append(ScanIssue(kind: kind, url: url, message: message))
    }

    private func applyVisualQASectionIfNeeded() {
        guard let value = ProcessInfo.processInfo.environment["LITTLE_TIDY_VISUAL_SECTION"] else {
            return
        }

        switch value {
        case "duplicates":
            selectedSection = .duplicates
        case "large-files":
            selectedSection = .largeFiles
        case "unused-apps":
            selectedSection = .unusedApps
        case "caches":
            selectedSection = .caches
        case "cleanup-plan":
            selectedSection = .cleanupPlan
        default:
            break
        }
    }

    private static func qaFixtureRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["LITTLE_TIDY_FIXTURE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let workingDirectoryCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("QA/LittleTidyFixture", isDirectory: true)
        if FileManager.default.fileExists(atPath: workingDirectoryCandidate.path) {
            return workingDirectoryCandidate
        }

        let sourceRootCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("QA/LittleTidyFixture", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceRootCandidate.path) {
            return sourceRootCandidate
        }

        return workingDirectoryCandidate
    }

    private struct SelectionSnapshot {
        let itemID: ReviewItem.ID
        let isSelected: Bool
        let duplicateCopySelections: [DuplicateCopyReview.ID: Bool]

        init(item: ReviewItem) {
            itemID = item.id
            isSelected = item.isSelected
            duplicateCopySelections = Dictionary(uniqueKeysWithValues: item.duplicateCopies.map { ($0.id, $0.isSelected) })
        }
    }

    private func persistApprovedFolders() {
        folderBookmarkStore.saveScanRoots(scanRoots)
        folderBookmarkStore.saveAppRoots(appRoots)
    }

    private func persistScanPreferences() {
        scanPreferencesStore.save(ScanPreferences(
            includeHiddenFiles: includeHiddenFiles,
            includeSystemFolders: includeSystemFolders,
            includeCaches: includeCaches,
            includeRelatedAppData: includeRelatedAppData,
            minimumDuplicateSize: minimumDuplicateSize,
            largeFileThreshold: largeFileThreshold
        ))
    }

    func sortedItems(_ items: [ReviewItem]) -> [ReviewItem] {
        items.sorted { lhs, rhs in
            switch reviewSortOption {
            case .largestFirst:
                if lhs.bytes != rhs.bytes {
                    return lhs.bytes > rhs.bytes
                }
            case .smallestFirst:
                if lhs.bytes != rhs.bytes {
                    return lhs.bytes < rhs.bytes
                }
            case .name:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            case .confidence:
                let lhsRank = confidenceRank(lhs.confidence)
                let rhsRank = confidenceRank(rhs.confidence)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
            case .location:
                let comparison = lhs.location.localizedStandardCompare(rhs.location)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }

            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func confidenceRank(_ confidence: Confidence) -> Int {
        switch confidence {
        case .high:
            return 0
        case .medium:
            return 1
        case .low:
            return 2
        }
    }

    private func cleanupReportItems(from result: TrashExecutionResult, plan: TrashPlan) -> [CleanupReportItem] {
        var planItemsByPath: [String: TrashPlanItem] = [:]
        for item in plan.items {
            planItemsByPath[item.sourceURL.standardizedFileURL.path] = item
        }

        let movedItems = result.trashed.map { trashed in
            let planItem = planItemsByPath[trashed.sourceURL.standardizedFileURL.path]
            return CleanupReportItem(
                sourceURL: trashed.sourceURL,
                destinationURL: trashed.trashURL,
                status: .moved,
                message: "Moved to Trash",
                reason: planItem?.reason ?? "Cleanup plan item",
                category: planItem?.category,
                bytes: planItem?.bytes ?? 0
            )
        }

        let skippedItems = result.skipped.map { url in
            let planItem = planItemsByPath[url.standardizedFileURL.path]
            return CleanupReportItem(
                sourceURL: url,
                destinationURL: nil,
                status: .skipped,
                message: "Source file was already missing",
                reason: planItem?.reason ?? "Cleanup plan item",
                category: planItem?.category,
                bytes: planItem?.bytes ?? 0
            )
        }

        let failedItems = result.failed.map { failed in
            let planItem = planItemsByPath[failed.url.standardizedFileURL.path]
            return CleanupReportItem(
                sourceURL: failed.url,
                destinationURL: nil,
                status: .failed,
                message: failed.error.localizedDescription,
                reason: planItem?.reason ?? "Cleanup plan item",
                category: planItem?.category,
                bytes: planItem?.bytes ?? 0
            )
        }

        return movedItems + skippedItems + failedItems
    }

    private static func reviewItems(from result: CleanupAnalysisResult) -> [ReviewItem] {
        let duplicateItems = result.duplicateGroups.map { group in
            let removableFiles = group.files.filter { $0.id != group.recommendedKeep?.id }
            let duplicateCopies = group.files.map { file in
                DuplicateCopyReview(
                    url: file.url,
                    bytes: file.fileSize,
                    isRecommendedKeep: file.id == group.recommendedKeep?.id,
                    isSelected: false
                )
            }
            return ReviewItem(
                category: .duplicate,
                title: group.files.first?.url.lastPathComponent ?? "Duplicate group",
                detail: "\(group.files.count) matching copies",
                location: group.recommendedKeep?.url.deletingLastPathComponent().path(percentEncoded: false) ?? "Unknown location",
                bytes: group.reclaimableBytes,
                confidence: group.confidence,
                reason: "Same size and SHA-256 hash. Keeps: \(group.recommendedKeep?.url.lastPathComponent ?? "one copy").",
                plannedURLs: removableFiles.map(\.url),
                contentHash: group.contentHash,
                bundleIdentifier: nil,
                lastOpenedDate: nil,
                installDate: nil,
                duplicateCopies: duplicateCopies,
                isSelected: false
            )
        }

        let largeFileItems = result.largeFiles.map { candidate in
            ReviewItem(
                category: .largeFile,
                title: candidate.file.url.lastPathComponent,
                detail: dateDetail(for: candidate.file),
                location: candidate.file.url.deletingLastPathComponent().path(percentEncoded: false),
                bytes: candidate.file.fileSize,
                confidence: candidate.confidence,
                reason: candidate.reason,
                plannedURLs: [candidate.file.url],
                contentHash: nil,
                bundleIdentifier: nil,
                lastOpenedDate: nil,
                installDate: nil,
                duplicateCopies: [],
                isSelected: false
            )
        }

        let appItems = result.unusedApps.map { classified in
            ReviewItem(
                category: .unusedApp,
                title: classified.record.displayName,
                detail: appDetail(for: classified),
                location: classified.record.appURL.deletingLastPathComponent().path(percentEncoded: false),
                bytes: classified.record.appSizeBytes,
                confidence: classified.record.confidence,
                reason: classified.reason,
                plannedURLs: [classified.record.appURL],
                contentHash: nil,
                bundleIdentifier: classified.record.bundleIdentifier,
                lastOpenedDate: classified.record.lastOpenedDate,
                installDate: classified.record.installDate,
                duplicateCopies: [],
                relatedData: classified.record.relatedData,
                isSelected: false
            )
        }

        let cacheItems = result.caches.map { candidate in
            ReviewItem(
                category: .cache,
                title: candidate.displayName,
                detail: cacheDetail(for: candidate),
                location: candidate.url.deletingLastPathComponent().path(percentEncoded: false),
                bytes: candidate.sizeBytes,
                confidence: candidate.confidence,
                reason: candidate.reason,
                plannedURLs: [candidate.url],
                contentHash: nil,
                bundleIdentifier: nil,
                lastOpenedDate: nil,
                installDate: nil,
                duplicateCopies: [],
                isSelected: false
            )
        }

        return duplicateItems + largeFileItems + appItems + cacheItems
    }

    private static func cacheDetail(for candidate: CacheCandidate) -> String {
        guard let lastModified = candidate.lastModified else {
            return "Regenerable cache"
        }
        return "Last updated \(lastModified.formatted(date: .abbreviated, time: .omitted))"
    }

    private static func dateDetail(for file: FileRecord) -> String {
        guard let date = file.lastAccessDate ?? file.modificationDate else {
            return "Date unavailable"
        }
        return "Last touched \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private static func appDetail(for classified: ClassifiedAppUsage) -> String {
        if let lastOpenedDate = classified.record.lastOpenedDate {
            return "Last opened \(lastOpenedDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return classified.category == .unknownUsage ? "Usage unknown" : classified.category.rawValue
    }

    private static func defaultScanRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]
        return names
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func defaultApplicationRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func isSystemRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let blockedPrefixes = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin"]
        return blockedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func uniqueExistingURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), !seenPaths.contains(path) else {
                return false
            }
            seenPaths.insert(path)
            return true
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? TrashPlanError else {
            return error.localizedDescription
        }

        switch error {
        case .emptyPlan:
            return "Select at least one item before cleaning."
        case .outsideApprovedRoots(let url):
            return "Blocked: \(url.lastPathComponent) is outside approved scan roots."
        case .duplicateGroupWouldRemoveAllCopies:
            return "Blocked: duplicate cleanup cannot remove every copy."
        case .systemAppBlocked(let url):
            return "Blocked: \(url.lastPathComponent) is a system app."
        case .symbolicLinkBlocked(let url):
            return "Blocked: \(url.lastPathComponent) is a symbolic link."
        }
    }

}
