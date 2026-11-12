import Foundation

/// Installers and already-expanded archives in the top level of `~/Downloads`.
/// Everything is `review`: these are the user's files, and the analyzer cannot
/// know whether an installer is still wanted.
public struct DownloadsClutterAnalyzer: Sendable {
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]
    public static let installerMinimumAgeDays = 30
    public static let archiveMinimumAgeDays = 60
    public static let recentGraceDays = 7

    private let downloads: URL
    private let now: @Sendable () -> Date
    private let installedAppNames: @Sendable () -> Set<String>

    public init(
        downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true),
        now: @escaping @Sendable () -> Date = Date.init,
        installedAppNames: @escaping @Sendable () -> Set<String> = DownloadsClutterAnalyzer.defaultInstalledAppNames
    ) {
        self.downloads = downloads
        self.now = now
        self.installedAppNames = installedAppNames
    }

    public func analyze() throws -> [EverydaySpaceItem] {
        let fileManager = FileManager.default
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: downloads,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )
        } catch let error as NSError where error.code == NSFileReadNoSuchFileError {
            return []
        } catch {
            throw EverydayAccessError.needsAccess
        }

        let apps = installedAppNames().map { $0.lowercased() }
        let current = now()
        var items: [EverydaySpaceItem] = []

        for url in children {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                  values.isSymbolicLink != true,
                  values.isPackage != true,
                  let modified = values.contentModificationDate else { continue }
            let ageDays = Calendar.current.dateComponents([.day], from: modified, to: current).day ?? 0
            guard ageDays >= Self.recentGraceDays else { continue }

            let ext = url.pathExtension.lowercased()
            if values.isDirectory != true, Self.installerExtensions.contains(ext), ageDays >= Self.installerMinimumAgeDays {
                let base = url.deletingPathExtension().lastPathComponent
                let installedMatch = Self.matchesInstalledApp(base, apps: apps)
                items.append(EverydaySpaceItem(
                    kind: .installers,
                    name: url.lastPathComponent,
                    detail: "Installer, \(ageDays) days old",
                    url: url,
                    bytes: FileSizing.allocatedBytes(at: url),
                    tier: .review,
                    reason: installedMatch
                        ? "An app with this name is already installed, and this installer is \(ageDays) days old."
                        : "An installer you downloaded \(ageDays) days ago.",
                    consequence: "You can download it again from its original source, if that source is still available.",
                    warning: nil
                ))
            } else if values.isDirectory != true, ext == "zip", ageDays >= Self.archiveMinimumAgeDays {
                let base = url.deletingPathExtension().lastPathComponent
                var isDirectory: ObjCBool = false
                let sibling = downloads.appendingPathComponent(base, isDirectory: true)
                if fileManager.fileExists(atPath: sibling.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    items.append(EverydaySpaceItem(
                        kind: .installers,
                        name: url.lastPathComponent,
                        detail: "Archive already expanded, \(ageDays) days old",
                        url: url,
                        bytes: FileSizing.allocatedBytes(at: url),
                        tier: .review,
                        reason: "The folder \"\(base)\" next to it holds the same content, and the archive is \(ageDays) days old.",
                        consequence: "The expanded folder stays. You can download the archive again if you know where it came from."
                    ))
                }
            }
        }

        // Installers of apps already installed first, then the biggest.
        return items.sorted {
            let lhs = $0.reason.hasPrefix("An app with this name")
            let rhs = $1.reason.hasPrefix("An app with this name")
            if lhs != rhs { return lhs }
            return $0.bytes > $1.bytes
        }
    }

    /// "Firefox 120.0" matches an installed "Firefox"; "Google Chrome" does not
    /// match an app called "Go". Matching is by whole leading words.
    static func matchesInstalledApp(_ filename: String, apps: [String]) -> Bool {
        let name = filename.lowercased()
        return apps.contains { app in
            guard app.count >= 3 else { return false }
            if name == app { return true }
            guard name.hasPrefix(app) else { return false }
            let next = name[name.index(name.startIndex, offsetBy: app.count)]
            return next == " " || next == "-" || next == "_" || next == "." || next.isNumber
        }
    }

    public static func defaultInstalledAppNames() -> Set<String> {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var names: Set<String> = []
        for root in roots {
            let urls = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                names.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return names
    }
}
