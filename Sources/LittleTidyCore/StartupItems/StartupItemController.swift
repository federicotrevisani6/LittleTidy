import Foundation

public enum StartupItemError: Error, Equatable, Sendable, LocalizedError {
    case notChangeable(String)
    case changedSinceScan
    case launchctlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notChangeable(let reason): reason
        case .changedSinceScan: "This item changed since the scan, so nothing was done. The list has been refreshed."
        case .launchctlFailed(let message): "macOS refused the change: \(message)"
        }
    }
}

/// Switches a user-level launchd item on or off through `launchctl`, called
/// with an explicit argument list and never through a shell. It never edits or
/// removes a property list or a program: the change is undone by switching the
/// item back on.
public struct StartupItemController: Sendable {
    private let runner: any DeveloperToolCommandRunning
    private let uid: uid_t
    private let reload: @Sendable () async -> [StartupItem]

    public init(
        runner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 10),
        uid: uid_t = getuid(),
        reload: @escaping @Sendable () async -> [StartupItem]
    ) {
        self.runner = runner
        self.uid = uid
        self.reload = reload
    }

    /// Returns a plain sentence about what will happen and when.
    @discardableResult
    public func setStartsAtLogin(_ enabled: Bool, item: StartupItem) async throws -> String {
        guard item.canChange else {
            throw StartupItemError.notChangeable(
                item.isApple
                    ? "Apple's own items are never changed."
                    : "Only your own login items can be changed. Items for all users or the system need administrator rights."
            )
        }
        // Re-read right before acting: refuse if anything moved since the scan.
        guard let fresh = await reload().first(where: { $0.path == item.path }),
              fresh.label == item.label, fresh.executable == item.executable, fresh.canChange else {
            throw StartupItemError.changedSinceScan
        }

        let domainTarget = "gui/\(uid)/\(fresh.label)"
        let launchctl = URL(fileURLWithPath: "/bin/launchctl")

        if enabled {
            try await run(launchctl, ["enable", domainTarget])
            return "It will start at your next login. LittleTidy did not start it now."
        }
        try await run(launchctl, ["disable", domainTarget])
        if fresh.isLoaded == true {
            do {
                try await run(launchctl, ["bootout", domainTarget])
                return "It will not start at login, and it has been stopped. Switch it back on to undo this."
            } catch {
                return "It will not start at your next login. It could not be stopped now and keeps running until you log out."
            }
        }
        return "It will not start at login. Switch it back on to undo this."
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws {
        do {
            _ = try await runner.run(executable: executable, arguments: arguments)
        } catch DeveloperToolCommandError.failed(_, _, let message) {
            throw StartupItemError.launchctlFailed(message.isEmpty ? "unknown error" : message)
        } catch {
            throw StartupItemError.launchctlFailed(error.localizedDescription)
        }
    }
}
