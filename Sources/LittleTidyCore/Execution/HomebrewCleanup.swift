import Foundation

/// Homebrew cleanup goes through `brew cleanup`, never through direct removal
/// of Cellar or cache folders. Only the standard installation prefixes are
/// accepted, so a scanned item can never name an arbitrary executable.
public enum HomebrewCleanup {
    public static let knownExecutables: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        URL(fileURLWithPath: "/usr/local/bin/brew")
    ]

    /// `-s` also scrubs downloads of current versions; `--prune=all` ignores
    /// cache age. Pinned formulae are always kept by Homebrew.
    public static let dryRunArguments = ["cleanup", "--dry-run", "-s", "--prune=all"]
    public static let cleanupArguments = ["cleanup", "-s", "--prune=all"]

    public static var environment: [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_COLOR": "1"
        ]) { _, new in new }
    }

    public static func isKnownExecutable(_ path: String) -> Bool {
        knownExecutables.contains { $0.path == path }
    }

    /// Parses Homebrew's summary line, for example
    /// "This operation would free approximately 8.2GB of disk space."
    /// Homebrew formats sizes with binary (1,024) multiples.
    public static func parseReclaimedBytes(_ output: Data) -> Int64? {
        let text = String(decoding: output, as: UTF8.self)
        guard let match = text.firstMatch(of: /(?:would free|has freed) approximately ([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB)/),
              let value = Double(match.1) else {
            return nil
        }
        let multiplier: Double = switch match.2 {
        case "KB": 1_024
        case "MB": 1_048_576
        case "GB": 1_073_741_824
        case "TB": 1_099_511_627_776
        default: 1
        }
        return Int64(value * multiplier)
    }
}
