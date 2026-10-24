import Foundation

public protocol DeveloperToolActivityChecking: Sendable {
    func isXcodeRunning() async -> Bool
    /// Paths currently open by any process of this user, or nil when the
    /// snapshot cannot be taken. Callers must treat nil as "in use".
    func openFileSnapshot() async -> OpenFileSnapshot?
    /// Whether a command-line test or build run (`xcodebuild`) is in progress.
    /// It can be creating or about to boot XCTest clones.
    func isXcodebuildRunning() async -> Bool
}

extension DeveloperToolActivityChecking {
    public func openFileSnapshot() async -> OpenFileSnapshot? { nil }
    public func isXcodebuildRunning() async -> Bool { false }
}

/// A point-in-time list of open file paths, used to decide whether a single
/// project's build data or a Simulator device is in use while Xcode runs.
public struct OpenFileSnapshot: Equatable, Sendable {
    public let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }

    /// Parses `lsof -F n` output, where each name field starts with "n".
    public init(lsofOutput: Data) {
        paths = String(decoding: lsofOutput, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                guard line.hasPrefix("n/") else { return nil }
                return String(line.dropFirst())
            }
    }

    public func containsPath(within url: URL) -> Bool {
        let root = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return paths.contains { $0 == root || $0.hasPrefix(prefix) }
    }
}

/// Checks the process table immediately before developer-storage cleanup.
/// Errors fail closed: if LittleTidy cannot prove Xcode is stopped, cleanup
/// remains blocked instead of risking files that Xcode may still be using.
public actor DeveloperToolActivityChecker: DeveloperToolActivityChecking {
    private let commandRunner: any DeveloperToolCommandRunning

    public init(commandRunner: any DeveloperToolCommandRunning = DeveloperToolCommandClient()) {
        self.commandRunner = commandRunner
    }

    public func isXcodeRunning() async -> Bool {
        await isProcessRunning("Xcode")
    }

    public func isXcodebuildRunning() async -> Bool {
        await isProcessRunning("xcodebuild")
    }

    private func isProcessRunning(_ name: String) async -> Bool {
        do {
            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-x", name]
            )
            return true
        } catch DeveloperToolCommandError.failed(_, let exitCode, _) where exitCode == 1 {
            return false
        } catch {
            return true
        }
    }

    /// Lists every open file once (about half a second) instead of walking
    /// each candidate with `lsof +D`, which scales with the size of the tree.
    public func openFileSnapshot() async -> OpenFileSnapshot? {
        do {
            let result = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-n", "-P", "-F", "n"]
            )
            let snapshot = OpenFileSnapshot(lsofOutput: result.standardOutput)
            return snapshot.paths.isEmpty ? nil : snapshot
        } catch {
            return nil
        }
    }
}
