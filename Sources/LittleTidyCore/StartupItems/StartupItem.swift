import Foundation

/// One launchd property list that starts something at login or boot.
///
/// This covers launchd items only. Apps can also register helpers through the
/// Service Management framework ("Login Items & Extensions" in System
/// Settings); those are not listed here, so no total built from this list may
/// claim to be everything that starts with the Mac.
public struct StartupItem: Identifiable, Equatable, Sendable {
    public enum Scope: String, Sendable {
        case user       // ~/Library/LaunchAgents
        case allUsers   // /Library/LaunchAgents
        case system     // /Library/LaunchDaemons

        public var label: String {
            switch self {
            case .user: "This user"
            case .allUsers: "All users"
            case .system: "System daemon"
            }
        }
    }

    public enum ExecutableState: String, Sendable {
        case present
        /// Confirmed missing. Never used for "could not read".
        case missing
        case unknown
    }

    public var id: String { path }
    public let label: String
    public let path: String
    public let executable: String?
    public let scope: Scope
    public let ownerName: String?
    public let executableState: ExecutableState
    /// Loaded in the user's launchd domain right now. Nil when unknown.
    public let isLoaded: Bool?
    /// Disabled in the user's launchd domain. Nil when unknown.
    public let isDisabled: Bool?
    public let issue: String?

    public init(
        label: String,
        path: String,
        executable: String?,
        scope: Scope,
        ownerName: String?,
        executableState: ExecutableState,
        isLoaded: Bool?,
        isDisabled: Bool?,
        issue: String?
    ) {
        self.label = label
        self.path = path
        self.executable = executable
        self.scope = scope
        self.ownerName = ownerName
        self.executableState = executableState
        self.isLoaded = isLoaded
        self.isDisabled = isDisabled
        self.issue = issue
    }

    public var isApple: Bool { label.hasPrefix("com.apple.") }

    /// Only this user's own items can be switched, and never Apple's. Anything
    /// in /Library is out: it would need administrator rights.
    public var canChange: Bool {
        scope == .user && !isApple && issue == nil && StartupItem.isSafeLabel(label)
    }

    public var isBroken: Bool { executableState == .missing }

    /// Labels go to `launchctl` as one argument; accept only plain ones.
    public static func isSafeLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 200 else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar)
        }
    }

    public var displayName: String { ownerName ?? label }
}

public enum StartupItemsParsing {
    /// `launchctl list`: lines of "PID<TAB>Status<TAB>Label".
    public static func loadedLabels(from output: String) -> Set<String> {
        var labels: Set<String> = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            if columns.count >= 3 { labels.insert(String(columns[2])) }
        }
        return labels
    }

    /// `launchctl print-disabled gui/<uid>`: lines such as `"label" => disabled`.
    public static func disabledLabels(from output: String) -> Set<String> {
        var labels: Set<String> = []
        for line in output.split(separator: "\n") {
            guard line.contains("=> disabled") || line.contains("=> true") else { continue }
            let parts = line.split(separator: "\"")
            if parts.count >= 2 { labels.insert(String(parts[1])) }
        }
        return labels
    }
}
