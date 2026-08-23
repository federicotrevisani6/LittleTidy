import Foundation

public struct DeveloperToolCommandResult: Equatable, Sendable {
    public let standardOutput: Data
    public let standardError: Data
    public let exitCode: Int32

    public init(standardOutput: Data, standardError: Data = Data(), exitCode: Int32 = 0) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public enum DeveloperToolCommandError: LocalizedError, Equatable {
    case unavailable(String)
    case failed(executable: String, exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let executable):
            "Required developer tool is unavailable: \(executable)"
        case .failed(let executable, let exitCode, let message):
            "\(executable) failed with exit code \(exitCode): \(message)"
        }
    }
}

public protocol DeveloperToolCommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult
}

public actor DeveloperToolCommandClient: DeveloperToolCommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DeveloperToolCommandError.unavailable(executable.path)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try Task.checkCancellation()
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()

        let result = DeveloperToolCommandResult(
            standardOutput: output,
            standardError: error,
            exitCode: process.terminationStatus
        )
        guard result.exitCode == 0 else {
            throw DeveloperToolCommandError.failed(
                executable: executable.path,
                exitCode: result.exitCode,
                message: String(decoding: error, as: UTF8.self)
            )
        }
        return result
    }
}
