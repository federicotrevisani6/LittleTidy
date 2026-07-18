import Foundation

public protocol DeveloperToolActivityChecking: Sendable {
    func isXcodeRunning() async -> Bool
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
        do {
            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-x", "Xcode"]
            )
            return true
        } catch DeveloperToolCommandError.failed(_, let exitCode, _) where exitCode == 1 {
            return false
        } catch {
            return true
        }
    }
}
