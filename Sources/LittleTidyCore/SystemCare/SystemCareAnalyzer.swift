import Foundation

public actor SystemCareAnalyzer {
    private let home: URL
    private let runner: any DeveloperToolCommandRunning
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, runner: any DeveloperToolCommandRunning = BoundedCommandRunner()) {
        self.home = home; self.runner = runner
    }
    public static let systemLocations: [StorageLocation] = [
        .init(name: "Archived temporary work", path: "/private/var/dirs_cleaner", explanation: "Archived temporary agent sessions and build output. Requires administrator access; contents need review."),
        .init(name: "System assets & simulator images", path: "/System/Library/AssetsV2", explanation: "Downloaded Apple resources and simulator images. Manage runtimes in Developer Storage; other resources are system managed."),
        .init(name: "Shared developer tools", path: "/Library/Developer", explanation: "Command line tools, simulator caches, and developer support. Mounted runtimes are excluded."),
        .init(name: "System logs & databases", path: "/private/var/db", explanation: "Includes diagnostics and system databases. Reported for diagnosis; not a cleanup candidate."),
        .init(name: "Spotlight search index", path: "/System/Volumes/Data/.Spotlight-V100", explanation: "System managed search metadata. Reindex only to address search problems."),
        .init(name: "Shared caches", path: "/Library/Caches", explanation: "Shared application caches. Administrator access may be required."),
        .init(name: "Temporary system files", path: "/private/var/folders", explanation: "Application temporary data. Some folders are protected or currently in use.")
    ]
    public var userLocations: [StorageLocation] {
        [
            ("Application data", "Library/Application Support", "Application settings, databases, and documents. Review individual apps before cleaning."),
            ("App containers", "Library/Containers", "Includes Docker virtual disks and sandboxed app data. Containers can hold personal documents."),
            ("Shared app data", "Library/Group Containers", "Shared application data, including Voice Memos. Personal data is not disposable cache."),
            ("Developer data", "Library/Developer", "Xcode, simulators, previews, and assistant resources. Connected device mounts are excluded."),
            ("Application caches", "Library/Caches", "Generated caches. Clean selected entries in Application Caches."),
            ("Bitrig", "Library/Bitrig", "Development environments and simulator data. Review projects before cleaning."),
            ("Android SDK", "Library/Android", "SDK packages and system images. Manage installed packages in Android Studio."),
            ("Android emulators", ".android", "Virtual devices and their app data."),
            ("Codex data", ".codex", "Sessions, packages, and worktrees. Worktrees may contain uncommitted changes."),
            ("Claude data", ".claude", "Sessions, caches, and agent resources. Project worktrees are separate."),
            ("Device backups", "Library/Application Support/MobileSync/Backup", "iPhone and iPad backups. Manage them using Finder."),
            ("Mail", "Library/Mail", "Mail messages and attachments. Manage data in Mail."),
            ("Messages", "Library/Messages", "Messages and attachments. Manage data in Messages.")
        ].map { StorageLocation(name: $0.0, path: home.appendingPathComponent($0.1).path, explanation: $0.2) }
    }
    public func storage(locations: [StorageLocation]) async throws -> [StorageMeasurement] {
        var measurements: [StorageMeasurement] = []
        for location in locations {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: location.path)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    measurements.append(.init(location: location, bytes: nil, issue: "Symbolic link excluded.")); continue
                }
                let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/du"), arguments: ["-x", "-I", "CoreDevice", "-sk", url.path])
                guard result.standardError.isEmpty,
                      let field = String(decoding: result.standardOutput, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).first,
                      let size = Int64(field), size >= 0, size <= Int64.max / 1024 else {
                    measurements.append(.init(location: location, bytes: nil, issue: "Incomplete measurement; size is unknown.")); continue
                }
                measurements.append(.init(location: location, bytes: size * 1024))
            } catch is CancellationError { throw CancellationError() }
            catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code) { continue }
                measurements.append(.init(location: location, bytes: nil, issue: error.localizedDescription))
            }
        }
        return measurements
    }
    public func allStorage() async throws -> [StorageMeasurement] {
        try await storage(locations: userLocations + Self.systemLocations)
    }
    public func protection() async throws -> [ProtectionCheck] {
        let checks: [(String, String, String, [String], String, String)] = [
            ("gatekeeper", "Gatekeeper", "/usr/sbin/spctl", ["--status"], "assessments enabled", "x-apple.systempreferences:com.apple.preference.security"),
            ("filevault", "FileVault", "/usr/bin/fdesetup", ["status"], "FileVault is On", "x-apple.systempreferences:com.apple.preference.security?FileVault"),
            ("sip", "System Integrity Protection", "/usr/bin/csrutil", ["status"], "status: enabled", "x-apple.systempreferences:com.apple.preference.security"),
            ("firewall", "Application firewall", "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], "State = 1", "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")
        ]
        var results: [ProtectionCheck] = []
        for (id, name, executable, arguments, enabled, settings) in checks {
            try Task.checkCancellation()
            do {
                let result = try await runner.run(executable: URL(fileURLWithPath: executable), arguments: arguments)
                let text = String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let state: ProtectionState
                if text.localizedCaseInsensitiveContains("custom configuration") { state = .attention }
                else if text.localizedCaseInsensitiveContains(enabled) { state = .enabled }
                else if text.localizedCaseInsensitiveContains("disabled") || text.contains("State = 0") || text.contains("FileVault is Off") { state = .attention }
                else { state = .unknown }
                results.append(.init(id: id, name: name, state: state, detail: text.isEmpty ? "Status unavailable." : text, settingsURL: settings))
            } catch is CancellationError { throw CancellationError() }
            catch { results.append(.init(id: id, name: name, state: .unknown, detail: error.localizedDescription, settingsURL: settings)) }
        }
        return results
    }
    public func startupEntries() -> [StartupEntry] {
        let roots = [home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]
        var entries: [StartupEntry] = []
        for root in roots {
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
                for url in urls where url.pathExtension == "plist" {
                    if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                    do {
                        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
                        entries.append(.init(name: plist?["Label"] as? String ?? url.lastPathComponent, path: url.path, executable: plist?["Program"] as? String ?? (plist?["ProgramArguments"] as? [String])?.first, isSystemWide: root.path.hasPrefix("/Library/"), issue: nil))
                    } catch { entries.append(.init(name: url.lastPathComponent, path: url.path, executable: nil, isSystemWide: root.path.hasPrefix("/Library/"), issue: error.localizedDescription)) }
                }
            } catch {
                if (error as NSError).code != NSFileReadNoSuchFileError {
                    entries.append(.init(name: root.lastPathComponent, path: root.path, executable: nil, isSystemWide: root.path.hasPrefix("/Library/"), issue: error.localizedDescription))
                }
            }
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func assessApplication(at url: URL) async throws -> String {
        guard url.pathExtension == "app", !url.path.hasPrefix("/System/") else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/sbin/spctl"), arguments: ["--assess", "--type", "execute", "--verbose=2", url.path])
        return "Accepted by Gatekeeper. " + String(decoding: result.standardError, as: UTF8.self)
    }
    public func localSnapshots() async throws -> String {
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/tmutil"), arguments: ["listlocalsnapshots", "/"])
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
    public func spotlightStatus() async throws -> String {
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/mdutil"), arguments: ["-s", "/"])
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
    public func maintenance(_ operation: MaintenanceOperation) async throws -> String {
        switch operation {
        case .flushDNS:
            _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/dscacheutil"), arguments: ["-flushcache"])
            _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["-HUP", "mDNSResponder"])
            return "DNS cache refreshed."
        case .rebuildSpotlight:
            let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/mdutil"), arguments: ["-E", "/"])
            return String(decoding: result.standardOutput, as: UTF8.self)
        }
    }
}
