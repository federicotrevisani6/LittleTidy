import Foundation

/// Time Machine local snapshots keep every block that existed when they were
/// taken, so removing older data frees nothing until macOS purges the snapshot.
/// LittleTidy only reads their names; it never creates or deletes snapshots.
public enum LocalSnapshotInventory {
    public static let listArguments = ["listlocalsnapshots", "/"]

    /// Parses `tmutil listlocalsnapshots /` lines such as
    /// "com.apple.TimeMachine.2026-10-24-190450.local". Times are local.
    public static func parseSnapshotDates(_ output: Data, timeZone: TimeZone = .current) -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return String(decoding: output, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                guard let match = line.firstMatch(of: /com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})\.local/) else {
                    return nil
                }
                return formatter.date(from: String(match.1))
            }
            .sorted()
    }
}
