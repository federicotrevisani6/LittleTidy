import Foundation
import Testing
@testable import LittleTidyCore

@Suite("System diagnosis and protection")
struct SystemCareTests {
    @Test("Failed and incomplete measurements remain unknown, not zero")
    func preservesAccessGaps() async throws {
        let directory = try TemporaryDirectory().url
        let location = StorageLocation(name: "Protected data", path: directory.path, explanation: "Fixture")
        for runner in [DiagnosticFixtureRunner(failure: true), DiagnosticFixtureRunner(output: "4096\tfixture\n", errorOutput: "Permission denied")] {
            let results = try await SystemCareAnalyzer(runner: runner).storage(locations: [location])
            #expect(results.count == 1)
            #expect(results[0].bytes == nil)
            #expect(results[0].issue != nil)
        }
    }
    @Test("Real directory measurement includes written data but excludes symlink roots")
    func measuresWithoutFollowingSymlinks() async throws {
        let directory = try TemporaryDirectory().url
        try Data(repeating: 42, count: 16384).write(to: directory.appendingPathComponent("payload"))
        let link = directory.appendingPathComponent("external")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let analyzer = SystemCareAnalyzer()
        let result = try await analyzer.storage(locations: [
            .init(name: "Data", path: directory.path, explanation: ""),
            .init(name: "Link", path: link.path, explanation: "")
        ])
        #expect((result[0].bytes ?? 0) >= 16384)
        #expect(result[1].bytes == nil)
        #expect(result[1].issue?.contains("Symbolic link") == true)
    }
    @Test("Security states distinguish disabled protections from unrecognized output")
    func doesNotTreatUnknownAsSafe() async throws {
        let disabled = try await SystemCareAnalyzer(runner: DiagnosticFixtureRunner(output: "assessments disabled\nFileVault is Off.\nstatus: disabled\nState = 0")).protection()
        #expect(disabled.allSatisfy { $0.state == .attention })
        let unknown = try await SystemCareAnalyzer(runner: DiagnosticFixtureRunner(output: "unrecognized operating system response")).protection()
        #expect(unknown.allSatisfy { $0.state == .unknown })
    }
    @Test("Timeout and cancellation terminate a real long-running command")
    func boundsCommandLifetime() async throws {
        do {
            _ = try await BoundedCommandRunner(timeout: 0.05).run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
            Issue.record("A timed out command was reported successful")
        } catch { #expect(error.localizedDescription.contains("timed out")) }
        let task = Task { try await BoundedCommandRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled command was reported successful") }
        catch { #expect(error is CancellationError) }
    }
    @Test("Agent build discovery recognizes Xcode metadata and preserves other scratchpad data")
    func findsTemporaryBuildsOnly() async throws {
        let home = try TemporaryDirectory().url
        let temp = home.appendingPathComponent("agent-temporary")
        let scratch = temp.appendingPathComponent("project/session/scratchpad")
        let build = scratch.appendingPathComponent("dd-ios")
        try FileManager.default.createDirectory(at: build.appendingPathComponent("Build"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/project/App.xcodeproj/project.xcworkspace"], format: .xml, options: 0)
        try plist.write(to: build.appendingPathComponent("info.plist"))
        try Data(repeating: 7, count: 4096).write(to: build.appendingPathComponent("Build/object.o"))
        let pretend = scratch.appendingPathComponent("dd-important-documents")
        try FileManager.default.createDirectory(at: pretend, withIntermediateDirectories: true)
        try Data("useful script".utf8).write(to: scratch.appendingPathComponent("script.py"))
        let result = try await DeveloperStorageAnalyzer(homeDirectory: home, commandRunner: DiagnosticFixtureRunner(failure: true), agentTemporaryRoot: temp).analyze()
        let builds = result.items.filter { $0.name.hasPrefix("Claude build data:") }
        #expect(builds.count == 1)
        #expect(builds.first?.url?.resolvingSymlinksInPath() == build.resolvingSymlinksInPath())
        #expect(builds.first?.recommendation == .review)
        #expect(builds.first?.recoverability == .recreatable)
        #expect(result.items.allSatisfy { $0.url != scratch && $0.url != pretend })
    }
    @Test("Startup inventory reads executable identity and skips redirected plists")
    func inventoriesStartupServices() async throws {
        let home = try TemporaryDirectory().url
        let root = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Label": "example.agent", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/agent"]], format: .xml, options: 0)
        let path = root.appendingPathComponent("example.plist")
        try plist.write(to: path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("redirect.plist"), withDestinationURL: path)
        let entries = await SystemCareAnalyzer(home: home).startupEntries()
        let local = entries.filter { !$0.isSystemWide }
        #expect(local.count == 1)
        #expect(local.first?.name == "example.agent")
        #expect(local.first?.executable == "/Applications/Example.app/Contents/MacOS/agent")
    }
}
private struct DiagnosticFixtureRunner: DeveloperToolCommandRunning {
    var output: String = ""
    var errorOutput: String = ""
    var failure = false
    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        if failure { throw DeveloperToolCommandError.failed(executable: executable.path, exitCode: 1, message: "Permission denied") }
        return .init(standardOutput: Data(output.utf8), standardError: Data(errorOutput.utf8))
    }
}
