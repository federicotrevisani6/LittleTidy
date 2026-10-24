import Foundation

public struct DeveloperStorageDecision: Equatable, Sendable {
    public let activity: StorageActivityState
    public let recoverability: StorageRecoverability
    public let mechanism: DeveloperCleanupMechanism
    public let consequence: CleanupConsequence
    public let recommendation: StorageRecommendation
    public let reason: String
}

public struct DeveloperStoragePolicy: Sendable {
    public init() {}

    public func decision(
        for category: DeveloperStorageCategory,
        isAvailable: Bool = true,
        isActive: Bool = false
    ) -> DeveloperStorageDecision {
        if isActive {
            let isSimulator = category == .simulatorDevices || category == .xctestDevices
            return DeveloperStorageDecision(
                activity: .active,
                recoverability: isSimulator ? .irreversible : .unknown,
                mechanism: isSimulator ? .simctl : .unsupported,
                consequence: .dataLossRisk,
                recommendation: .protected,
                reason: "Currently active. LittleTidy protects it from cleanup."
            )
        }

        switch category {
        case .derivedData:
            return DeveloperStorageDecision(
                activity: .inactive,
                recoverability: .recreatable,
                mechanism: .trash,
                consequence: .temporarySlowdown,
                recommendation: .recommended,
                reason: "Xcode rebuilds this data automatically. The first build may take longer."
            )
        case .simulatorDevices:
            if !isAvailable {
                return DeveloperStorageDecision(
                    activity: .unavailable,
                    recoverability: .irreversible,
                    mechanism: .simctl,
                    consequence: .dataLossRisk,
                    recommendation: .recommended,
                    reason: "This device is unavailable to Simulator and can be removed with simctl."
                )
            }
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .irreversible,
                mechanism: .simctl,
                consequence: .dataLossRisk,
                recommendation: .review,
                reason: "Review the device state and contents before removing it permanently."
            )
        case .simulatorRuntimes:
            return DeveloperStorageDecision(
                activity: isAvailable ? .unknown : .unavailable,
                recoverability: .reinstallable,
                mechanism: .xcodeManaged,
                consequence: .redownloadRequired,
                recommendation: isAvailable ? .review : .unclassified,
                reason: isAvailable
                    ? "Removing a runtime requires a later download before using matching simulators."
                    : "The runtime appears unavailable, but LittleTidy cannot yet prove a supported removal path."
            )
        case .xctestDevices:
            // Only devices registered in simctl's "testing" set reach this
            // decision; unregistered XCTest data uses `unverifiedXCTestDecision`.
            return DeveloperStorageDecision(
                activity: isAvailable ? .inactive : .unavailable,
                recoverability: .recreatable,
                mechanism: .simctl,
                consequence: .temporarySlowdown,
                recommendation: .recommended,
                reason: "Clone created by Xcode for parallel testing. Xcode creates new clones on the next test run. Removal uses simctl and cannot be undone."
            )
        case .deviceSupport:
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .recreatable,
                mechanism: .trash,
                consequence: .debuggingImpact,
                recommendation: .review,
                reason: "Xcode may need to recreate support files when a matching device reconnects."
            )
        case .packageCaches:
            return DeveloperStorageDecision(
                activity: .inactive,
                recoverability: .recreatable,
                mechanism: .trash,
                consequence: .temporarySlowdown,
                recommendation: .recommended,
                reason: "Package manager caches will be re-downloaded automatically on the next project build or restore."
            )
        case .aiModelsAndAgents:
            return DeveloperStorageDecision(
                activity: .inactive,
                recoverability: .reinstallable,
                mechanism: .trash,
                consequence: .redownloadRequired,
                recommendation: .review,
                reason: "Local model weights and derived indexes can be regenerated or redownloaded."
            )
        case .aiCaches:
            return DeveloperStorageDecision(
                activity: .inactive,
                recoverability: .recreatable,
                mechanism: .trash,
                consequence: .temporarySlowdown,
                recommendation: .recommended,
                reason: "Generated caches, logs, and temporary agent data can be recreated as needed."
            )
        case .aiGeneratedArtifacts:
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .trashRestorable,
                mechanism: .trash,
                consequence: .dataLossRisk,
                recommendation: .review,
                reason: "Sessions and generated artifacts can be large, but may contain useful transcripts, screenshots, or documents. Review before moving them to Trash."
            )
        case .androidEmulators:
            return DeveloperStorageDecision(
                activity: .inactive,
                recoverability: .reinstallable,
                mechanism: .trash,
                consequence: .redownloadRequired,
                recommendation: .review,
                reason: "Android Virtual Device (AVD) images can be recreated via Android Studio Device Manager."
            )
        case .archives:
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .trashRestorable,
                mechanism: .trash,
                consequence: .debuggingImpact,
                recommendation: .protected,
                reason: "Archives may be required for re-exporting or crash symbolication and are never preselected."
            )
        case .testArtifacts:
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .trashRestorable,
                mechanism: .trash,
                consequence: .debuggingImpact,
                recommendation: .review,
                reason: "Test results can contain logs and attachments needed for investigations."
            )
        case .otherDeveloperData:
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .unknown,
                mechanism: .unsupported,
                consequence: .unknown,
                recommendation: .unclassified,
                reason: "LittleTidy found this storage but cannot classify it safely yet."
            )
        }
    }

    /// XCTest data that simctl does not list in its "testing" device set.
    /// Ownership cannot be proven, so it remains diagnosis-only.
    public func unverifiedXCTestDecision() -> DeveloperStorageDecision {
        DeveloperStorageDecision(
            activity: .unknown,
            recoverability: .unknown,
            mechanism: .unsupported,
            consequence: .dataLossRisk,
            recommendation: .unclassified,
            reason: "simctl does not list this XCTest data as a test device, so LittleTidy reports it for diagnosis only."
        )
    }

    /// A shutdown XCTest clone while a test session uses the same device set.
    /// Xcode can boot any clone of the set mid-run, so none is removable.
    public func xctestSessionActiveDecision() -> DeveloperStorageDecision {
        DeveloperStorageDecision(
            activity: .active,
            recoverability: .recreatable,
            mechanism: .simctl,
            consequence: .dataLossRisk,
            recommendation: .protected,
            reason: "An Xcode test session is using clones from this set. LittleTidy protects every clone until the run finishes."
        )
    }

    /// Temporary files of a Claude session whose process has ended and that
    /// nothing has written to for an hour.
    public func closedClaudeSessionDecision() -> DeveloperStorageDecision {
        DeveloperStorageDecision(
            activity: .inactive,
            recoverability: .trashRestorable,
            mechanism: .trash,
            consequence: .negligible,
            recommendation: .recommended,
            reason: "Temporary files of a closed Claude session: screenshots, videos, builds, and scratch files. The conversation transcript in ~/.claude/projects is kept."
        )
    }

    /// A closed session that was written to in the last hour may be resuming.
    public func recentClaudeSessionDecision() -> DeveloperStorageDecision {
        DeveloperStorageDecision(
            activity: .recentlyUsed,
            recoverability: .trashRestorable,
            mechanism: .trash,
            consequence: .dataLossRisk,
            recommendation: .review,
            reason: "This session closed less than an hour ago or was just written to. Review it before moving it to Trash."
        )
    }

    /// Old Homebrew versions and downloads, removed by Homebrew itself.
    public func homebrewCleanupDecision() -> DeveloperStorageDecision {
        DeveloperStorageDecision(
            activity: .inactive,
            recoverability: .reinstallable,
            mechanism: .homebrewCleanup,
            consequence: .negligible,
            recommendation: .recommended,
            reason: "Outdated formula versions and cached downloads. Homebrew removes them with brew cleanup, skips pinned formulae, and can reinstall any version later."
        )
    }
}
