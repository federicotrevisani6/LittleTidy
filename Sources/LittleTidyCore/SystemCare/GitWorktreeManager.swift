import Foundation

public struct GitWorktreeRecord: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let commonDirectory: String
    public let head: String
    public let branch: String?
    public let locked: Bool
    public let prunable: Bool
}

public struct WorktreeInspection: Sendable {
    public let worktree: GitWorktreeRecord
    public let bytes: Int64?
    public let changes: [String]
    public let activity: String
    public let gitStatus: String
    public let blockers: [String]
    public var canRemove: Bool { blockers.isEmpty }
}

public struct WorktreeDiscovery: Sendable {
    public let worktrees: [GitWorktreeRecord]
    public let issues: [String]
}

public protocol WorktreeActivityChecking: Sendable {
    /// Nil means no open files were observed. A reason means active or unknown.
    func blockingReason(at path: String) async -> String?
}

public struct WorktreeActivityChecker: WorktreeActivityChecking {
    private let runner = BoundedCommandRunner(timeout: 15)
    public init() {}
    public func blockingReason(at path: String) async -> String? {
        if await DeveloperToolActivityChecker(commandRunner: runner).isXcodeRunning() {
            return "Xcode is running, or its activity could not be checked."
        }
        do {
            let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/sbin/lsof"), arguments: ["-n", "-P", "-F", "pcn", "+D", path])
            if !result.standardError.isEmpty { return "Open-file activity could not be fully checked." }
            return result.standardOutput.isEmpty ? nil : "Processes have open files or a working directory in this worktree. Close them before removal."
        } catch DeveloperToolCommandError.failed(_, let code, let message) where code == 1 && message.isEmpty {
            return nil
        } catch { return "Activity unknown: \(error.localizedDescription)" }
    }
}

/// Only registered linked worktrees inside the approved root are removable.
/// Git runs with a clean environment, no hooks, no fsmonitor and no force flag.
public actor GitWorktreeManager {
    private let root: URL
    private let runner: any DeveloperToolCommandRunning
    private let activity: any WorktreeActivityChecking
    private let fm = FileManager.default
    private let git = URL(fileURLWithPath: "/usr/bin/git")
    private let options = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-c", "core.hooksPath=/dev/null", "-c", "gc.auto=0", "-c", "submodule.recurse=false"]
    public init(root: URL, activity: any WorktreeActivityChecking = WorktreeActivityChecker()) {
        self.root = root
        self.activity = activity
        runner = BoundedCommandRunner(timeout: 15, environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": fm.homeDirectoryForCurrentUser.path, "GIT_TERMINAL_PROMPT": "0"])
    }
    public func discover() async throws -> WorktreeDiscovery {
        try validate(root)
        var queue: [(URL, Int)] = [(root, 0)], visited = 0
        var records: [String: GitWorktreeRecord] = [:], issues: [String] = []
        let deadline = Date().addingTimeInterval(60)
        while !queue.isEmpty {
            try Task.checkCancellation()
            let (directory, depth) = queue.removeFirst(); visited += 1
            if Date() > deadline { issues.append("Discovery stopped after one minute; results are partial."); break }
            if visited > 2000 { issues.append("Discovery stopped after 2,000 folders; results are partial."); break }
            let marker = directory.appendingPathComponent(".git")
            if let type = (try? fm.attributesOfItem(atPath: marker.path))?[.type] as? FileAttributeType, type == .typeRegular || type == .typeDirectory {
                do {
                    for item in try await registered(at: directory) where contains(URL(fileURLWithPath: item.path)) { records[item.path] = item }
                } catch { issues.append("\(directory.path): \(error.localizedDescription)") }
                continue
            }
            guard depth < 4 else { continue }
            do {
                for child in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                    guard !["CoreDevice", "node_modules", ".build", ".git"].contains(child.lastPathComponent),
                          !["app", "framework", "bundle", "photoslibrary"].contains(child.pathExtension.lowercased()),
                          (try? fm.attributesOfItem(atPath: child.path))?[.type] as? FileAttributeType == .typeDirectory else { continue }
                    queue.append((child, depth + 1))
                }
            } catch { issues.append("\(directory.path): \(error.localizedDescription)") }
        }
        return .init(worktrees: records.values.sorted { $0.path < $1.path }, issues: issues)
    }
    public func inspect(_ record: GitWorktreeRecord) async throws -> WorktreeInspection {
        let url = URL(fileURLWithPath: record.path)
        try validate(url)
        guard let current = try await registered(at: url).first(where: { $0.path == record.path }), current.commonDirectory == record.commonDirectory else { throw failure("Registration changed. Scan again.") }
        var blockers: [String] = [], changes: [String] = []
        var gitStatus = "Working file status was not checked."
        if current.locked { blockers.append("This worktree is locked by Git.") }
        if current.prunable { blockers.append("Git reports stale registration. Repair it manually.") }
        if let branch = current.branch {
            let tip = String(decoding: try await run(at: url, arguments: ["rev-parse", "--verify", branch]), as: UTF8.self).trimmingCharacters(in: .newlines)
            if tip != current.head { blockers.append("The branch no longer preserves this checkout's HEAD. Review its commits manually.") }
        } else { blockers.append("Detached HEAD: preserve its commits on a branch before removal.") }
        // Filters may run arbitrary repository programs during status. Refuse them.
        let filters = try await optionalGit(at: url, arguments: ["config", "--null", "--name-only", "--get-regexp", "^filter\\..*\\.(clean|process|required)$"])
        if !filters.isEmpty {
            blockers.append("Repository content filters are configured. Inspect this worktree in your Git client; LittleTidy does not run them.")
        } else {
            let flags = try await run(at: url, arguments: ["ls-files", "-v", "-z"])
            if flags.split(separator: 0).contains(where: { $0.first == 83 || ($0.first.map { $0 >= 97 && $0 <= 122 } ?? false) }) {
                blockers.append("The index hides file changes (skip-worktree or assume-unchanged). Restore normal tracking before removal.")
            }
            let stages = try await run(at: url, arguments: ["ls-files", "--stage", "-z"])
            if stages.split(separator: 0).contains(where: { String(decoding: $0, as: UTF8.self).hasPrefix("160000 ") }) { blockers.append("Submodules require manual review.") }
            let status = try await run(at: url, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching", "--ignore-submodules=none"])
            gitStatus = status.isEmpty ? "No tracked changes, untracked files, or ignored data found." : "Local changes or ignored data found; removal is blocked."
            changes = status.split(separator: 0).prefix(100).map { String(decoding: $0, as: UTF8.self) }
            if !status.isEmpty { blockers.append("Tracked changes, untracked files, or ignored data remain. Preserve them before removal.") }
        }
        let activityReason = await activity.blockingReason(at: record.path)
        if let activityReason { blockers.append(activityReason) }
        let size = try await SystemCareAnalyzer(runner: BoundedCommandRunner(timeout: 5)).storage(locations: [.init(name: url.lastPathComponent, path: url.path, explanation: "Git worktree")]).first
        return .init(worktree: current, bytes: size?.bytes, changes: changes,
                     activity: activityReason ?? "No open files observed. Background agents can still resume; stop the owning agent before removing.", gitStatus: gitStatus, blockers: blockers)
    }
    public func remove(_ inspected: WorktreeInspection, allowPermanentDeletion: Bool, ownerStoppedConfirmed: Bool) async throws {
        guard allowPermanentDeletion, ownerStoppedConfirmed, inspected.canRemove else { throw failure("Permanent removal is not authorized, or the worktree is protected.") }
        let fresh = try await inspect(inspected.worktree)
        guard fresh.canRemove, fresh.worktree == inspected.worktree else { throw failure("Worktree state changed or removal is blocked. Check again.") }
        let url = URL(fileURLWithPath: fresh.worktree.path)
        // Repeat file checks after the activity/size probes, immediately before Git removal.
        let filters = try await optionalGit(at: url, arguments: ["config", "--null", "--name-only", "--get-regexp", "^filter\\..*\\.(clean|process|required)$"])
        guard filters.isEmpty else { throw failure("Content filter configuration changed. Removal blocked.") }
        let status = try await run(at: url, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching", "--ignore-submodules=none"])
        guard status.isEmpty else { throw failure("Local data appeared after the review. Removal blocked.") }
        try Task.checkCancellation()
        // No --force: Git performs its own final dirty/locked/submodule checks.
        _ = try await runner.run(executable: git, arguments: options + ["--git-dir=\(fresh.worktree.commonDirectory)", "worktree", "remove", "--", fresh.worktree.path])
        guard !fm.fileExists(atPath: fresh.worktree.path) else { throw failure("Git did not remove the worktree.") }
    }
    private func registered(at url: URL) async throws -> [GitWorktreeRecord] {
        try validate(url)
        let marker = url.appendingPathComponent(".git")
        let type = try fm.attributesOfItem(atPath: marker.path)[.type] as? FileAttributeType
        guard type == .typeDirectory || type == .typeRegular else { throw failure("Not a Git checkout.") }
        let top = String(decoding: try await run(at: url, arguments: ["rev-parse", "--show-toplevel"]), as: UTF8.self).trimmingCharacters(in: .newlines)
        guard top == url.path else { throw failure("Git checkout boundary does not match the selected folder.") }
        let common = String(decoding: try await run(at: url, arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"]), as: UTF8.self).trimmingCharacters(in: .newlines)
        try noLinks(URL(fileURLWithPath: common))
        let actualGit = String(decoding: try await run(at: url, arguments: ["rev-parse", "--absolute-git-dir"]), as: UTF8.self).trimmingCharacters(in: .newlines)
        try noLinks(URL(fileURLWithPath: actualGit))
        let data = try await run(at: url, arguments: ["worktree", "list", "--porcelain", "-z"])
        var records: [GitWorktreeRecord] = [], fields: [String] = []
        for part in data.split(separator: 0, omittingEmptySubsequences: false) {
            if part.isEmpty {
                if let pathField = fields.first(where: { $0.hasPrefix("worktree ") }), let headField = fields.first(where: { $0.hasPrefix("HEAD ") }), !fields.contains("bare") {
                    let path = String(pathField.dropFirst(9))
                    // Main checkout has a directory marker; only linked .git files qualify.
                    if (try? fm.attributesOfItem(atPath: path + "/.git"))?[.type] as? FileAttributeType == .typeRegular {
                        records.append(.init(path: path, commonDirectory: common, head: String(headField.dropFirst(5)), branch: fields.first(where: { $0.hasPrefix("branch ") }).map { String($0.dropFirst(7)) }, locked: fields.contains(where: { $0 == "locked" || $0.hasPrefix("locked ") }), prunable: fields.contains(where: { $0 == "prunable" || $0.hasPrefix("prunable ") })))
                    }
                }
                fields = []
            } else { fields.append(String(decoding: part, as: UTF8.self)) }
        }
        return records
    }
    private func run(at url: URL, arguments: [String]) async throws -> Data {
        try await runner.run(executable: git, arguments: options + ["-C", url.path] + arguments).standardOutput
    }
    private func optionalGit(at url: URL, arguments: [String]) async throws -> Data {
        do { return try await run(at: url, arguments: arguments) }
        catch DeveloperToolCommandError.failed(_, let code, let message) where code == 1 && message.isEmpty { return Data() }
    }
    private func contains(_ url: URL) -> Bool { url.path == root.path || url.path.hasPrefix(root.path + "/") }
    private func validate(_ url: URL) throws {
        guard contains(url), !url.pathComponents.contains("CoreDevice"), !url.path.contains("\n"), !url.pathComponents.contains(".."), !url.pathComponents.contains("."), !url.path.hasPrefix("/System/"), url.path != "/System" else { throw failure("Outside the approved worktree folder.") }
        try noLinks(url)
    }
    private func noLinks(_ url: URL) throws {
        var cursor = URL(fileURLWithPath: "/")
        for component in url.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            guard try fm.attributesOfItem(atPath: cursor.path)[.type] as? FileAttributeType != .typeSymbolicLink else { throw failure("Symbolic links are not inspected or removed: \(cursor.path)") }
        }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "LittleTidy.Worktrees", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
