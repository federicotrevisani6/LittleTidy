import Foundation

public struct StorageLocation: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let explanation: String
    public init(name: String, path: String, explanation: String) {
        self.name = name; self.path = path; self.explanation = explanation
    }
}

public struct StorageMeasurement: Identifiable, Codable, Equatable, Sendable {
    public var id: String { location.id }
    public let location: StorageLocation
    /// Nil means unknown, never an empty directory.
    public let bytes: Int64?
    public let issue: String?
    public init(location: StorageLocation, bytes: Int64?, issue: String? = nil) {
        self.location = location; self.bytes = bytes; self.issue = issue
    }
}

public enum ProtectionState: String, Codable, Sendable { case enabled, attention, unknown }
public struct ProtectionCheck: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: ProtectionState
    public let detail: String
    public let settingsURL: String
    public init(id: String, name: String, state: ProtectionState, detail: String, settingsURL: String) {
        self.id = id; self.name = name; self.state = state; self.detail = detail; self.settingsURL = settingsURL
    }
}

public struct StartupEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let executable: String?
    public let isSystemWide: Bool
    public let issue: String?
}

public enum MaintenanceOperation: String, CaseIterable, Codable, Sendable {
    case flushDNS, rebuildSpotlight
    public var title: String {
        switch self { case .flushDNS: "Refresh DNS cache"; case .rebuildSpotlight: "Rebuild Spotlight index" }
    }
    public var explanation: String {
        switch self {
        case .flushDNS: "Refresh name resolution when websites fail to load. This does not reclaim disk space."
        case .rebuildSpotlight: "Rebuild search metadata when results are missing. Indexing uses CPU and disk temporarily."
        }
    }
}

/// The helper exposes fixed operations, never a root shell or an arbitrary path.
@objc public protocol SystemCareHelperProtocol {
    func measureSystemStorage(reply: @escaping @Sendable (Data?, String?) -> Void)
    func performMaintenance(_ operation: String, reply: @escaping @Sendable (String?, String?) -> Void)
}

public enum SystemCareHelperIdentity {
    public static let service = "com.federicotrevisani.LittleTidy.Helper"
    public static let plist = service + ".plist"
    public static let team = "3VU7K9SUV8"
    public static let appRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"com.federicotrevisani.LittleTidy\""
    public static let helperRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(service)\""
}
