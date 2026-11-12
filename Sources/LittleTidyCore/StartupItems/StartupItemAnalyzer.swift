import Foundation

public struct StartupItemsResult: Equatable, Sendable {
    public let items: [StartupItem]
    /// Folders that could not be read: an access issue, not an empty list.
    public let accessIssues: [String]

    public init(items: [StartupItem], accessIssues: [String]) {
        self.items = items
        self.accessIssues = accessIssues
    }
}

/// Reads launchd property lists and adds what makes them understandable:
/// which app owns each one, whether the program it starts still exists, and
/// whether it is loaded or disabled for this user. Read-only.
public struct StartupItemAnalyzer: Sendable {
    public typealias EntryProvider = @Sendable () async -> [StartupEntry]

    private let entries: EntryProvider
    private let runner: any DeveloperToolCommandRunning
    private let uid: uid_t
    private let fileExists: @Sendable (String) -> Bool
    private let home: String

    public init(
        entries: @escaping EntryProvider = { await SystemCareAnalyzer().startupEntries() },
        runner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 10),
        uid: uid_t = getuid(),
        home: String = NSHomeDirectory(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.entries = entries
        self.runner = runner
        self.uid = uid
        self.home = home
        self.fileExists = fileExists
    }

    public func analyze() async -> StartupItemsResult {
        let found = await entries()
        let loaded = await loadedLabels()
        let disabled = await disabledLabels()

        var items: [StartupItem] = []
        var issues: [String] = []
        for entry in found {
            if let issue = entry.issue, entry.executable == nil, !entry.path.hasSuffix(".plist") {
                issues.append("\(entry.name): \(issue)")
                continue
            }
            let scope = Self.scope(of: entry.path, home: home)
            let state = Self.executableState(entry.executable, fileExists: fileExists)
            items.append(StartupItem(
                label: entry.name,
                path: entry.path,
                executable: entry.executable,
                scope: scope,
                ownerName: Self.ownerName(from: entry.executable),
                executableState: entry.issue == nil ? state : .unknown,
                isLoaded: loaded.map { $0.contains(entry.name) },
                isDisabled: scope == .user ? disabled.map { $0.contains(entry.name) } : nil,
                issue: entry.issue
            ))
        }
        let ordered = items.sorted {
            if $0.isBroken != $1.isBroken { return $0.isBroken }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return StartupItemsResult(items: ordered, accessIssues: issues)
    }

    static func scope(of path: String, home: String) -> StartupItem.Scope {
        if path.hasPrefix(home + "/Library/LaunchAgents") { return .user }
        if path.hasPrefix("/Library/LaunchDaemons") { return .system }
        return .allUsers
    }

    /// Present only when the file is there; missing only when it is confirmed
    /// not there; unknown when there is nothing to check.
    static func executableState(_ executable: String?, fileExists: (String) -> Bool) -> StartupItem.ExecutableState {
        guard let executable, executable.hasPrefix("/") else { return .unknown }
        return fileExists(executable) ? .present : .missing
    }

    /// "/Applications/Some App.app/Contents/..." -> "Some App".
    static func ownerName(from executable: String?) -> String? {
        guard let executable, let range = executable.range(of: ".app/") ?? executable.range(of: ".app", options: .backwards, range: nil, locale: nil) else { return nil }
        let prefix = executable[..<range.lowerBound]
        guard let name = prefix.split(separator: "/").last else { return nil }
        return String(name)
    }

    private func loadedLabels() async -> Set<String>? {
        guard let output = try? await runner.run(executable: URL(fileURLWithPath: "/bin/launchctl"), arguments: ["list"]) else { return nil }
        return StartupItemsParsing.loadedLabels(from: String(decoding: output.standardOutput, as: UTF8.self))
    }

    private func disabledLabels() async -> Set<String>? {
        guard let output = try? await runner.run(executable: URL(fileURLWithPath: "/bin/launchctl"), arguments: ["print-disabled", "gui/\(uid)"]) else { return nil }
        return StartupItemsParsing.disabledLabels(from: String(decoding: output.standardOutput, as: UTF8.self))
    }
}
