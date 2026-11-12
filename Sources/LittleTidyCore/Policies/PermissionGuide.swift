import Foundation

/// What a macOS permission unlocks in LittleTidy and which Smart Care cards
/// depend on it, so the guide can explain it before anyone hits a wall.
public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case fullDiskAccess

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullDiskAccess: "Full Disk Access"
        }
    }

    /// One sentence on what it unlocks and what happens without it.
    public var unlocks: String {
        switch self {
        case .fullDiskAccess:
            "Lets LittleTidy read the Trash, iPhone and iPad backups and Mail attachments. Without it those cards say \"Needs access\" and nothing else changes."
        }
    }

    public var affectedCards: [SmartCareCardID] {
        switch self {
        case .fullDiskAccess: [.trash, .iosBackups, .mailAttachments]
        }
    }

    public var settingsURL: URL {
        switch self {
        case .fullDiskAccess: FullDiskAccess.settingsURL
        }
    }
}

/// "Allowed" is shown only when a probe confirmed it. A failed or ambiguous
/// probe is "not confirmed", never a claim that access is missing or granted.
public enum PermissionState: String, Sendable {
    case confirmed
    case notConfirmed

    public var label: String {
        switch self {
        case .confirmed: "Allowed"
        case .notConfirmed: "Not confirmed"
        }
    }
}

public struct PermissionItem: Identifiable, Equatable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: PermissionKind
    public let state: PermissionState
}

public enum PermissionGuide {
    public static func items(fullDiskAccessConfirmed: Bool) -> [PermissionItem] {
        PermissionKind.allCases.map { kind in
            switch kind {
            case .fullDiskAccess:
                PermissionItem(kind: kind, state: fullDiskAccessConfirmed ? .confirmed : .notConfirmed)
            }
        }
    }

    /// Whether the first-launch guide should appear: something is not
    /// confirmed and the person has not chosen "Not now" before.
    public static func shouldPresent(items: [PermissionItem], dismissedBefore: Bool) -> Bool {
        !dismissedBefore && items.contains { $0.state == .notConfirmed }
    }

    /// The cards that stay in "Needs access" because of what is not confirmed.
    public static func affectedCards(in items: [PermissionItem]) -> [SmartCareCardID] {
        items.filter { $0.state == .notConfirmed }.flatMap { $0.kind.affectedCards }
    }
}
