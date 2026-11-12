import Foundation
import Testing
@testable import LittleTidyCore

private actor RecordingRunner: DeveloperToolCommandRunning {
    private(set) var calls: [[String]] = []
    var failOn: String?
    var outputs: [String: String] = [:]

    init(failOn: String? = nil, outputs: [String: String] = [:]) {
        self.failOn = failOn
        self.outputs = outputs
    }

    func run(executable: URL, arguments: [String]) async throws -> DeveloperToolCommandResult {
        calls.append(arguments)
        if let failOn, arguments.first == failOn {
            throw DeveloperToolCommandError.failed(executable: executable.path, exitCode: 1, message: "denied")
        }
        let key = arguments.first ?? ""
        return DeveloperToolCommandResult(standardOutput: Data((outputs[key] ?? "").utf8))
    }
}

private func item(
    label: String = "com.example.helper",
    path: String = "/Users/test/Library/LaunchAgents/com.example.helper.plist",
    executable: String? = "/Applications/Example.app/Contents/MacOS/helper",
    scope: StartupItem.Scope = .user,
    loaded: Bool? = false,
    issue: String? = nil
) -> StartupItem {
    StartupItem(label: label, path: path, executable: executable, scope: scope, ownerName: "Example",
                executableState: .present, isLoaded: loaded, isDisabled: false, issue: issue)
}

@Suite("Startup items: model and parsing")
struct StartupItemModelTests {
    @Test func onlyOwnNonAppleReadableItemsCanChange() {
        #expect(item().canChange)
        #expect(!item(label: "com.apple.something").canChange)
        #expect(!item(scope: .allUsers).canChange)
        #expect(!item(scope: .system).canChange)
        #expect(!item(issue: "unreadable").canChange)
    }

    @Test func unsafeLabelsAreNeverPassedToLaunchctl() {
        #expect(StartupItem.isSafeLabel("com.example.helper-1_a"))
        #expect(!StartupItem.isSafeLabel("com.example helper"))
        #expect(!StartupItem.isSafeLabel("a;rm -rf /"))
        #expect(!StartupItem.isSafeLabel("../x"))
        #expect(!StartupItem.isSafeLabel(""))
        #expect(!item(label: "bad label").canChange)
    }

    @Test func parsesLoadedAndDisabledLabels() {
        let list = "PID\tStatus\tLabel\n123\t0\tcom.example.one\n-\t0\tcom.example.two\n"
        #expect(StartupItemsParsing.loadedLabels(from: list) == ["com.example.one", "com.example.two"])
        let disabled = """
        disabled services = {
            "com.example.off" => disabled
            "com.example.on" => enabled
        }
        """
        #expect(StartupItemsParsing.disabledLabels(from: disabled) == ["com.example.off"])
    }

    @Test func scopeOwnerAndExecutableStateAreDerived() {
        #expect(StartupItemAnalyzer.scope(of: "/Users/test/Library/LaunchAgents/x.plist", home: "/Users/test") == .user)
        #expect(StartupItemAnalyzer.scope(of: "/Library/LaunchAgents/x.plist", home: "/Users/test") == .allUsers)
        #expect(StartupItemAnalyzer.scope(of: "/Library/LaunchDaemons/x.plist", home: "/Users/test") == .system)
        #expect(StartupItemAnalyzer.ownerName(from: "/Applications/Some App.app/Contents/MacOS/x") == "Some App")
        #expect(StartupItemAnalyzer.ownerName(from: "/usr/local/bin/tool") == nil)
        #expect(StartupItemAnalyzer.executableState("/gone", fileExists: { _ in false }) == .missing)
        #expect(StartupItemAnalyzer.executableState("/here", fileExists: { _ in true }) == .present)
        #expect(StartupItemAnalyzer.executableState(nil, fileExists: { _ in true }) == .unknown)
        #expect(StartupItemAnalyzer.executableState("relative", fileExists: { _ in false }) == .unknown)
    }
}

@Suite("Startup items: analyzer")
struct StartupItemAnalyzerTests {
    @Test func brokenItemsComeFirstAndAreMarkedOnlyWhenConfirmedMissing() async {
        let entries: [StartupEntry] = [
            StartupEntry(name: "com.a.fine", path: "/Users/test/Library/LaunchAgents/a.plist", executable: "/there", isSystemWide: false, issue: nil),
            StartupEntry(name: "com.b.gone", path: "/Users/test/Library/LaunchAgents/b.plist", executable: "/missing", isSystemWide: false, issue: nil),
            StartupEntry(name: "com.c.unreadable", path: "/Users/test/Library/LaunchAgents/c.plist", executable: nil, isSystemWide: false, issue: "could not read")
        ]
        let runner = RecordingRunner(outputs: ["list": "PID\tStatus\tLabel\n1\t0\tcom.a.fine\n"])
        let result = await StartupItemAnalyzer(entries: { entries }, runner: runner, uid: 501, home: "/Users/test",
                                               fileExists: { $0 == "/there" }).analyze()
        #expect(result.items.first?.label == "com.b.gone")
        #expect(result.items.first?.isBroken == true)
        let unreadable = result.items.first { $0.label == "com.c.unreadable" }
        #expect(unreadable?.executableState == .unknown)
        #expect(unreadable?.canChange == false)
        #expect(result.items.first { $0.label == "com.a.fine" }?.isLoaded == true)
    }

    @Test func anUnreadableFolderIsAnAccessIssueNotAnEmptyList() async {
        let entries = [StartupEntry(name: "LaunchAgents", path: "/Library/LaunchAgents", executable: nil, isSystemWide: true, issue: "Permission denied")]
        let result = await StartupItemAnalyzer(entries: { entries }, runner: RecordingRunner(), uid: 501, home: "/Users/test").analyze()
        #expect(result.items.isEmpty)
        #expect(result.accessIssues.count == 1)
    }

    @Test func stateIsUnknownWhenLaunchctlCannotAnswer() async {
        let entries = [StartupEntry(name: "com.a.x", path: "/Users/test/Library/LaunchAgents/a.plist", executable: "/e", isSystemWide: false, issue: nil)]
        let result = await StartupItemAnalyzer(entries: { entries }, runner: RecordingRunner(failOn: "list"), uid: 501, home: "/Users/test",
                                               fileExists: { _ in true }).analyze()
        #expect(result.items.first?.isLoaded == nil)
    }
}

@Suite("Startup items: controller")
struct StartupItemControllerTests {
    @Test func disableCallsLaunchctlWithAnExplicitArgumentList() async throws {
        let target = item(loaded: false)
        let runner = RecordingRunner()
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
        try await controller.setStartsAtLogin(false, item: target)
        #expect(await runner.calls == [["disable", "gui/501/com.example.helper"]])
    }

    @Test func aLoadedItemIsAlsoBootedOut() async throws {
        let target = item(loaded: true)
        let runner = RecordingRunner()
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
        let message = try await controller.setStartsAtLogin(false, item: target)
        #expect(await runner.calls == [["disable", "gui/501/com.example.helper"], ["bootout", "gui/501/com.example.helper"]])
        #expect(message.contains("stopped"))
    }

    @Test func enableOnlyEnablesAndDoesNotStartIt() async throws {
        let target = item(loaded: false)
        let runner = RecordingRunner()
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
        try await controller.setStartsAtLogin(true, item: target)
        #expect(await runner.calls == [["enable", "gui/501/com.example.helper"]])
    }

    @Test func appleSystemAndAllUsersItemsAreRefusedWithoutRunningAnything() async {
        let runner = RecordingRunner()
        for target in [item(label: "com.apple.x"), item(scope: .allUsers), item(scope: .system)] {
            let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
            await #expect(throws: StartupItemError.self) { try await controller.setStartsAtLogin(false, item: target) }
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func anItemThatChangedSinceTheScanAbortsBeforeAnyCommand() async {
        let scanned = item()
        let changed = item(executable: "/somewhere/else")
        let runner = RecordingRunner()
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [changed] })
        await #expect(throws: StartupItemError.changedSinceScan) { try await controller.setStartsAtLogin(false, item: scanned) }
        let gone = StartupItemController(runner: runner, uid: 501, reload: { [] })
        await #expect(throws: StartupItemError.changedSinceScan) { try await gone.setStartsAtLogin(false, item: scanned) }
        #expect(await runner.calls.isEmpty)
    }

    @Test func aFailingLaunchctlIsReportedAndNothingElseRuns() async {
        let target = item(loaded: true)
        let runner = RecordingRunner(failOn: "disable")
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
        await #expect(throws: StartupItemError.self) { try await controller.setStartsAtLogin(false, item: target) }
        #expect(await runner.calls == [["disable", "gui/501/com.example.helper"]])
    }

    @Test func aFailedBootoutStillReportsThatTheItemWillNotStartAtLogin() async throws {
        let target = item(loaded: true)
        let runner = RecordingRunner(failOn: "bootout")
        let controller = StartupItemController(runner: runner, uid: 501, reload: { [target] })
        let message = try await controller.setStartsAtLogin(false, item: target)
        #expect(message.contains("next login"))
    }
}
