import Foundation
import LittleTidyCore

extension ScanReviewStore {
    private static let aiCategories: Set<DeveloperStorageCategory> = [.aiModelsAndAgents, .aiCaches, .aiGeneratedArtifacts]

    /// Builds the Smart Care cards from what the existing analyzers found.
    func smartCareCards(startupItemCount: Int) -> [SmartCareCard] {
        var inputs = SmartCareInputs()

        let developerItems = developerStorageInventory.items
        inputs.entries[.developer] = developerItems
            .filter { !Self.aiCategories.contains($0.category) }
            .map(Self.entry(for:))
        inputs.entries[.aiTools] = developerItems
            .filter { Self.aiCategories.contains($0.category) }
            .map(Self.entry(for:))
        if isScanningDeveloperStorage {
            inputs.states[.developer] = .scanning
            inputs.states[.aiTools] = .scanning
        }

        inputs.entries[.caches] = items(for: .cache).map { item in
            SmartCareEntry(
                path: item.plannedURLs.first?.path ?? item.id.uuidString,
                bytes: item.bytes,
                // The app never preselects caches (see `suggestedWithoutCaches`),
                // so they are Review here too: a person decides, not a default.
                tier: .review
            )
        }
        if isScanning { inputs.states[.caches] = .scanning }

        if trashNeedsAccess {
            inputs.states[.trash] = .needsAccess("Allow Full Disk Access to read the Trash.")
        } else if let trashPreview {
            inputs.entries[.trash] = trashPreview.items.map {
                SmartCareEntry(path: $0.url.path, bytes: $0.bytes, tier: .review)
            }
        }

        inputs.entries[.unusedApps] = items(for: .unusedApp).map { item in
            // Removing an app is always a decision, never a default.
            SmartCareEntry(path: item.plannedURLs.first?.path ?? item.id.uuidString, bytes: item.bytes, tier: .review)
        }
        if isScanning { inputs.states[.unusedApps] = .scanning }

        if let date = developerStorageInventory.latestLocalSnapshotAt {
            inputs.infoText[.snapshots] = "Latest local snapshot \(date.formatted(date: .abbreviated, time: .shortened)). macOS releases this space itself when it is needed."
        }
        if startupItemCount > 0 {
            inputs.infoText[.startupItems] = "\(startupItemCount) items start with your Mac."
        }

        return SmartCareBuilder.cards(from: inputs)
    }

    private static func entry(for item: DeveloperStorageItem) -> SmartCareEntry {
        SmartCareEntry(
            path: item.url?.path ?? "developer-item:\(item.id)",
            bytes: item.bytes,
            tier: item.recommendation
        )
    }

    // MARK: - Actions

    /// Selects the card's recommended items and opens the existing
    /// confirmation (Cleanup Plan or Developer Storage). Nothing is removed here.
    func prepareSmartCareClean(_ card: SmartCareCard) {
        guard card.canClean else { return }
        let recommendedPaths = Set(card.entries.filter { $0.tier == .recommended }.map(\.path))
        switch card.cardID {
        case .caches:
            clearSelection()
            for item in items(for: .cache) where item.confidence == .high {
                if let path = item.plannedURLs.first?.path, recommendedPaths.contains(path) {
                    setSelection(for: item, isSelected: true)
                }
            }
            selectedSection = .cleanupPlan
        case .developer, .aiTools:
            selectedDeveloperStorageItemIDs = []
            for item in developerStorageInventory.items where item.recommendation == .recommended {
                let path = item.url?.path ?? "developer-item:\(item.id)"
                if recommendedPaths.contains(path) {
                    setDeveloperStorageItemSelection(item, isSelected: true)
                }
            }
            selectedSection = .developerStorage
        case .trash, .unusedApps, .snapshots, .startupItems:
            break
        }
    }

    func reviewSmartCare(_ card: SmartCareCard) {
        switch card.cardID {
        case .developer, .aiTools: selectedSection = .developerStorage
        case .caches: selectedSection = .caches
        case .trash: openTrash()
        case .unusedApps: selectedSection = .unusedApps
        case .snapshots, .startupItems: selectedSection = .maintenance
        }
    }

    func refreshTrashPreview() {
        let emptier = makeTrashEmptier()
        let lastCleanup = lastCleanupTrashPaths
        Task { [weak self] in
            let outcome: Result<TrashEmptyPreview, Error> = await Task.detached(priority: .utility) {
                Result { try emptier.preview(lastCleanupPaths: lastCleanup) }
            }.value
            guard let self else { return }
            switch outcome {
            case .success(let preview):
                self.trashPreview = preview
                self.trashNeedsAccess = false
            case .failure:
                self.trashPreview = nil
                self.trashNeedsAccess = true
            }
        }
    }

    /// Permanent removal of the Trash's contents. Only called after the
    /// Trash card's own confirmation sheet.
    func emptyTrash() {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        trashEmptyResult = nil
        let emptier = makeTrashEmptier()
        Task { [weak self] in
            let result = await emptier.empty()
            guard let self else { return }
            self.trashEmptyResult = result
            self.isEmptyingTrash = false
            self.lastCleanupTrashPaths = []
            self.refreshTrashPreview()
        }
    }

    private func makeTrashEmptier() -> TrashEmptier {
        TrashEmptier { await DeveloperToolActivityChecker().openFileSnapshot() }
    }

    /// What the sidebar badge shows: recommended bytes only.
    var smartCareSafeBytes: Int64 {
        SmartCareBuilder.headline(for: smartCareCards(startupItemCount: 0)).safeBytes
    }

    func startSmartCareScan() {
        if !isScanning { startOrCancelScan() }
        // A scan already running must not be restarted: that made the card
        // look finished while it was still working.
        if !isScanningDeveloperStorage { refreshDeveloperStorage() }
        refreshTrashPreview()
    }

    // MARK: - Clean all safe

    /// What the header button would clean right now. Cheap, so views can read it.
    var cleanAllCandidate: SmartCareCleanPlan {
        SmartCareCleanPlanner.plan(from: developerStorageInventory.items, xcodeIsRunning: isXcodeRunning)
    }

    var canCleanAllSafe: Bool {
        !isScanning && !isScanningDeveloperStorage && !isCleaningDeveloperStorage && !cleanAllCandidate.isEmpty
    }

    /// Builds the preview shown in the confirmation sheet. Nothing is removed.
    func prepareCleanAllSafe() {
        guard !isScanning, !isScanningDeveloperStorage, !isCleaningDeveloperStorage else { return }
        refreshXcodeRunningState()
        cleanAllResult = nil
        cleanAllPlan = SmartCareCleanPlanner.plan(from: developerStorageInventory.items, xcodeIsRunning: isXcodeRunning)
    }

    func dismissCleanAllSafe() {
        cleanAllPlan = nil
        cleanAllResult = nil
    }

    /// Runs the previewed items through the existing executor. It rechecks
    /// every safety rule (Xcode lock guard, open files, simctl state) for each
    /// item at execution time, so the preview is never a permission.
    func confirmCleanAllSafe() {
        guard let plan = cleanAllPlan, !plan.isEmpty, !isCleaningDeveloperStorage else { return }
        isCleaningDeveloperStorage = true
        developerCleanupResult = nil
        let mode = deletionMode
        let items = plan.items
        Task { [weak self] in
            let result = await DeveloperStorageCleanupExecutor().execute(items: items, deletionMode: mode)
            guard let self else { return }
            self.removeCleanedDeveloperItems(result)
            self.developerCleanupResult = result
            self.cleanAllResult = result
            self.snapshotReleaseResult = nil
            self.snapshotReleaseErrorMessage = nil
            self.isCleaningDeveloperStorage = false
            self.selectedDeveloperStorageItemIDs = []
            self.refreshDeveloperStorage()
        }
    }
}
