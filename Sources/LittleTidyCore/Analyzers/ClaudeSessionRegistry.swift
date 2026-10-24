import Darwin
import Foundation

/// Claude Code records each running session in ~/.claude/sessions/<pid>.json
/// with its session ID. A session is live while that process exists. Session
/// folders under /private/tmp/claude-<uid> are named after the session ID, so
/// a folder whose session is not live belongs to a closed session.
public struct ClaudeSessionRegistry: Sendable {
    /// `externalIdentifier` prefix for a closed session's cleanup item.
    public static let itemIdentifierPrefix = "claude-session:"

    private let sessionsDirectory: URL
    private let isProcessAlive: @Sendable (Int32) -> Bool

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isProcessAlive: @escaping @Sendable (Int32) -> Bool = ClaudeSessionRegistry.processExists
    ) {
        self.sessionsDirectory = homeDirectory.appendingPathComponent(".claude/sessions", isDirectory: true)
        self.isProcessAlive = isProcessAlive
    }

    /// Lowercased IDs of sessions whose process is running, or nil when the
    /// registry cannot be read. Callers must treat nil as "every session may
    /// be live" and offer no session for cleanup.
    public func liveSessionIDs() -> Set<String>? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        var live: Set<String> = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = record["sessionId"] as? String,
                  let pid = (record["pid"] as? NSNumber)?.int32Value else {
                continue
            }
            if isProcessAlive(pid) {
                live.insert(sessionID.lowercased())
            }
        }
        return live
    }

    /// `kill(pid, 0)` checks existence without sending a signal. EPERM means
    /// the process exists but belongs to someone else, so it counts as alive.
    @Sendable public static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
