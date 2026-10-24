import Foundation

public struct LocalSnapshotReleaseResult: Codable, Equatable, Sendable {
    public let requestedBytes: Int64
    public let snapshotsBefore: Int
    public let snapshotsAfter: Int
    public let freeBytesBefore: Int64?
    public let freeBytesAfter: Int64?

    public init(requestedBytes: Int64, snapshotsBefore: Int, snapshotsAfter: Int, freeBytesBefore: Int64?, freeBytesAfter: Int64?) {
        self.requestedBytes = requestedBytes
        self.snapshotsBefore = snapshotsBefore
        self.snapshotsAfter = snapshotsAfter
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
    }

    public var snapshotsRemoved: Int { max(0, snapshotsBefore - snapshotsAfter) }

    public var measuredFreedBytes: Int64? {
        guard let freeBytesBefore, let freeBytesAfter else { return nil }
        return freeBytesAfter - freeBytesBefore
    }
}

/// Releases space held by Time Machine local snapshots through macOS's own
/// thinning, the mechanism it uses under space pressure. macOS chooses which
/// snapshots to remove, oldest first, until the requested amount is
/// reclaimable. LittleTidy never names a snapshot or deletes one directly, and
/// external Time Machine backups are not affected.
public actor LocalSnapshotReleaser {
    /// Highest urgency, so macOS acts now instead of when space runs out.
    public static let urgency = "4"

    private let runner: any DeveloperToolCommandRunning
    private let freeSpace: @Sendable () -> Int64?

    public init(
        runner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 300),
        freeSpace: @escaping @Sendable () -> Int64? = DeveloperStorageCleanupExecutor.homeVolumeFreeBytes
    ) {
        self.runner = runner
        self.freeSpace = freeSpace
    }

    public static func thinArguments(bytes: Int64) -> [String] {
        ["thinlocalsnapshots", "/", String(bytes), urgency]
    }

    public func release(bytes: Int64) async throws -> LocalSnapshotReleaseResult {
        guard bytes > 0 else {
            throw DeveloperToolCommandError.failed(executable: "/usr/bin/tmutil", exitCode: -1, message: "Nothing to release.")
        }
        let tmutil = URL(fileURLWithPath: "/usr/bin/tmutil")
        let before = try await snapshotCount(tmutil)
        let freeBefore = freeSpace()
        _ = try await runner.run(executable: tmutil, arguments: Self.thinArguments(bytes: bytes))
        let after = try await snapshotCount(tmutil)
        return LocalSnapshotReleaseResult(
            requestedBytes: bytes,
            snapshotsBefore: before,
            snapshotsAfter: after,
            freeBytesBefore: freeBefore,
            freeBytesAfter: freeSpace()
        )
    }

    private func snapshotCount(_ tmutil: URL) async throws -> Int {
        let result = try await runner.run(executable: tmutil, arguments: LocalSnapshotInventory.listArguments)
        return LocalSnapshotInventory.parseSnapshotDates(result.standardOutput).count
    }
}
