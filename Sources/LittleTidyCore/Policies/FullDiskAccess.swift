import Foundation

public enum FullDiskAccess: Sendable {
    /// Tests whether the current process has Full Disk Access (FDA)
    /// by attempting to inspect known TCC-protected directories.
    public static var isGranted: Bool {
        let home = NSHomeDirectory()
        let probePaths = [
            (home as NSString).appendingPathComponent("Library/Safari"),
            (home as NSString).appendingPathComponent("Library/Mail"),
            (home as NSString).appendingPathComponent("Library/Suggestions")
        ]

        for path in probePaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    _ = try FileManager.default.contentsOfDirectory(atPath: path)
                    return true
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
                        return false
                    }
                    if nsError.domain == NSPOSIXErrorDomain && nsError.code == 1 {
                        return false
                    }
                }
            }
        }

        // Fallback test for environments where Safari directory might be missing
        let fallbackSafariFile = (home as NSString).appendingPathComponent("Library/Safari/Bookmarks.plist")
        if FileManager.default.fileExists(atPath: fallbackSafariFile) {
            return FileManager.default.isReadableFile(atPath: fallbackSafariFile)
        }

        return false
    }

    /// URL to open macOS System Settings directly to Privacy & Security -> Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
