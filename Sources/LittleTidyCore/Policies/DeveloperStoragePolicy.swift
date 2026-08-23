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
            return DeveloperStorageDecision(
                activity: .active,
                recoverability: category == .simulatorDevices ? .irreversible : .unknown,
                mechanism: category == .simulatorDevices ? .simctl : .unsupported,
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
            return DeveloperStorageDecision(
                activity: .unknown,
                recoverability: .unknown,
                mechanism: .unsupported,
                consequence: .dataLossRisk,
                recommendation: .unclassified,
                reason: "XCTest data is reported for diagnosis only until ownership and activity can be proven."
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
}
