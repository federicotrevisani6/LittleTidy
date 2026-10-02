import Darwin
import Foundation

/// Runs explicit executables without a shell. Output is drained to files so
/// simultaneous stdout/stderr cannot deadlock a scan. Every process is bounded.
public struct BoundedCommandRunner: DeveloperToolCommandRunning {
    public let timeout: TimeInterval
    public let environment: [String: String]?
    public init(timeout: TimeInterval = 30, environment: [String: String]? = nil) {
        self.timeout = timeout; self.environment = environment
    }

    public func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        let operation = CommandOperation(executable: executable, arguments: arguments, timeout: timeout, environment: environment)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) { try operation.perform() }.value
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class CommandOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private let timeout: TimeInterval
    init(executable: URL, arguments: [String], timeout: TimeInterval, environment: [String: String]?) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = (environment ?? ProcessInfo.processInfo.environment).merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }
        self.timeout = timeout
    }
    func cancel() {
        lock.lock()
        cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
    }
    func perform() throws -> DeveloperToolCommandResult {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("LittleTidy-command-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        fm.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fm.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forUpdating: outURL)
        let err = try FileHandle(forUpdating: errURL)
        defer { try? out.close(); try? err.close() }
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let deadline = Date().addingTimeInterval(timeout)
        var stoppedAt: Date?
        var failure: String?
        while process.isRunning {
            lock.lock(); let wasCancelled = cancelled; lock.unlock()
            if stoppedAt == nil {
                let oversized = [outURL, errURL].contains {
                    ((try? fm.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber)?.intValue ?? 0 > 4_194_304
                }
                if wasCancelled || Date() > deadline || oversized {
                    failure = oversized ? "Command output exceeded the scan limit." : "Operation timed out; size or status is unknown."
                    stoppedAt = Date()
                    process.terminate()
                }
            } else if Date().timeIntervalSince(stoppedAt!) > 1 {
                kill(process.processIdentifier, SIGKILL)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw CancellationError() }
        try out.seek(toOffset: 0); try err.seek(toOffset: 0)
        let output = try out.read(upToCount: 4_194_304) ?? Data()
        let errors = try err.read(upToCount: 4_194_304) ?? Data()
        if let failure {
            throw DeveloperToolCommandError.failed(executable: process.executableURL!.path, exitCode: -1, message: failure)
        }
        guard process.terminationStatus == 0 else {
            throw DeveloperToolCommandError.failed(executable: process.executableURL!.path, exitCode: process.terminationStatus, message: String(decoding: errors.prefix(4096), as: UTF8.self) + (errors.count > 4096 ? "\nAdditional command diagnostics omitted." : ""))
        }
        return DeveloperToolCommandResult(standardOutput: output, standardError: errors, exitCode: 0)
    }
}
