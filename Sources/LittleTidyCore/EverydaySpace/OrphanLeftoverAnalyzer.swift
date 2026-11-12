import Foundation

/// App data in `~/Library` whose app is no longer installed. The danger is a
/// wrong match: removing another app's data. So it matches only exact bundle
/// identifiers, never names, never Group Containers, never Apple's, and it
/// lists nothing at all when it cannot prove the app is gone.
public struct OrphanLeftoverAnalyzer: Sendable {
    public static let minimumAgeDays = 90
    public static let libraryFolders = [
        "Application Support", "Caches", "Preferences", "Containers",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs"
    ]

    public typealias SpotlightApps = @Sendable () async -> [URL]?

    private let home: URL
    private let appRoots: [URL]
    private let runningBundleIDs: @Sendable () -> Set<String>
    private let spotlightApps: SpotlightApps
    private let now: @Sendable () -> Date

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appRoots: [URL] = [],
        runningBundleIDs: @escaping @Sendable () -> Set<String> = { [] },
        spotlightApps: @escaping SpotlightApps = OrphanLeftoverAnalyzer.mdfindApps,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.home = home
        self.appRoots = appRoots
        self.runningBundleIDs = runningBundleIDs
        self.spotlightApps = spotlightApps
        self.now = now
    }

    public var checkedRoots: [URL] {
        var roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     home.appendingPathComponent("Applications", isDirectory: true)] + appRoots
        var seen: Set<String> = []
        roots = roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return roots
    }

    public func analyze() async throws -> EverydayScanResult {
        // Without Spotlight we cannot see apps on other volumes: fail closed.
        guard let spotlight = await spotlightApps() else {
            return EverydayScanResult(kind: .appLeftovers, items: [], problem: .cannotVerify)
        }

        var installed: Set<String> = runningBundleIDs().reduce(into: Set<String>()) { $0.insert($1.lowercased()) }
        for root in checkedRoots { try Task.checkCancellation(); installed.formUnion(Self.bundleIDs(inAppsOf: root)) }
        for app in spotlight { try Task.checkCancellation(); installed.formUnion(Self.bundleIDs(ofApp: app)) }

        let rootsText = checkedRoots.map { $0.path.replacingOccurrences(of: home.path, with: "~") }.joined(separator: ", ")
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let fileManager = FileManager.default
        var items: [EverydaySpaceItem] = []
        var accessDenied = false
        let current = now()

        for folder in Self.libraryFolders {
            try Task.checkCancellation()
            let base = library.appendingPathComponent(folder, isDirectory: true)
            guard fileManager.fileExists(atPath: base.path) else { continue }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch {
                accessDenied = true
                continue
            }
            for url in children {
                guard let id = Self.identifier(from: url.lastPathComponent), Self.isReverseDNS(id), !id.lowercased().hasPrefix("com.apple.") else { continue }
                guard !FileSizing.isSymbolicLink(url) else { continue }
                guard !Self.isInstalled(id.lowercased(), in: installed) else { continue }
                guard let age = Self.ageDays(of: url, now: current), age >= Self.minimumAgeDays else { continue }
                items.append(EverydaySpaceItem(
                    kind: .appLeftovers,
                    name: id,
                    detail: "\(folder) · last changed \(age) days ago",
                    url: url,
                    bytes: FileSizing.allocatedBytes(at: url),
                    tier: .review,
                    reason: "No app with this ID was found in: \(rootsText), nor through Spotlight.",
                    consequence: "Settings, caches or saved data of an app that is no longer installed. If you reinstall the app it starts fresh.",
                    bundleID: id
                ))
            }
        }

        let problem: EverydayScanResult.Problem? = (accessDenied && items.isEmpty) ? .needsAccess : nil
        return EverydayScanResult(kind: .appLeftovers, items: items.sorted { $0.bytes > $1.bytes }, problem: problem)
    }

    // MARK: - Matching

    /// Equal to an installed ID, or a dot-suffix of one (helpers and extensions).
    static func isInstalled(_ id: String, in installed: Set<String>) -> Bool {
        if installed.contains(id) { return true }
        return installed.contains { id.hasPrefix($0 + ".") }
    }

    /// "com.foo.bar.plist" -> "com.foo.bar"; "com.foo.bar.savedState" likewise.
    static func identifier(from name: String) -> String? {
        for suffix in [".plist", ".savedState", ".binarycookies", ".lockfile"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Reverse-DNS shaped, with at least three parts: "com.vendor.app".
    static func isReverseDNS(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, id.count <= 200 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) }
        }
    }

    /// The newest of the item's own date and its direct children's.
    static func ageDays(of url: URL, now: Date) -> Int? {
        func modified(_ url: URL) -> Date? {
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard var newest = modified(url) else { return nil }
        if let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for child in children { if let date = modified(child), date > newest { newest = date } }
        }
        return Calendar.current.dateComponents([.day], from: newest, to: now).day
    }

    // MARK: - Installed bundle IDs

    /// Apps one or two levels under a root (for folders such as Utilities).
    static func bundleIDs(inAppsOf root: URL) -> Set<String> {
        var ids: Set<String> = []
        let fileManager = FileManager.default
        guard let level1 = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return ids }
        for url in level1 {
            if url.pathExtension == "app" {
                ids.formUnion(bundleIDs(ofApp: url))
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let level2 = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for inner in level2 where inner.pathExtension == "app" { ids.formUnion(bundleIDs(ofApp: inner)) }
            }
        }
        return ids
    }

    /// The app's own ID plus the IDs of helpers, login items, XPC services,
    /// plug-ins and frameworks inside it. Only the folders where an app keeps
    /// those are walked, so a large app does not cost a full traversal.
    static func bundleIDs(ofApp app: URL) -> Set<String> {
        var ids: Set<String> = []
        if let id = bundleID(at: app) { ids.insert(id.lowercased()) }
        let fileManager = FileManager.default
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        for folder in ["Library/LoginItems", "Library/LaunchServices", "PlugIns", "XPCServices", "Frameworks", "Helpers", "MacOS"] {
            let base = contents.appendingPathComponent(folder, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                if let id = bundleID(at: child) { ids.insert(id.lowercased()) }
                // Helper apps inside a framework folder: one more level.
                if child.pathExtension == "framework",
                   let nested = try? fileManager.contentsOfDirectory(at: child.appendingPathComponent("Versions/Current/Helpers"), includingPropertiesForKeys: nil) {
                    for helper in nested { if let id = bundleID(at: helper) { ids.insert(id.lowercased()) } }
                }
            }
        }
        return ids
    }

    private static func bundleID(at bundle: URL) -> String? {
        for relative in ["Contents/Info.plist", "Info.plist", "Resources/Info.plist", "Versions/Current/Resources/Info.plist"] {
            let url = bundle.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty else { continue }
            return id
        }
        return nil
    }

    // MARK: - Spotlight

    /// Every app bundle Spotlight knows, on any mounted volume. Nil when the
    /// query fails, so the caller can refuse to list anything.
    public static let mdfindApps: SpotlightApps = {
        let runner = BoundedCommandRunner(timeout: 20)
        guard let result = try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/mdfind"),
            arguments: ["kMDItemContentType == 'com.apple.application-bundle'"]
        ) else { return nil }
        let paths = String(decoding: result.standardOutput, as: UTF8.self).split(separator: "\n").map(String.init)
        return paths.filter { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: $0) }
    }
}
