import CoreServices
import Foundation

public enum AppUsageCategory: String, Sendable {
    case probablyUnused
    case possiblyUnused
    case unknownUsage
    case recentlyUsed
}

public struct ClassifiedAppUsage: Sendable {
    public let record: AppUsageRecord
    public let category: AppUsageCategory
    public let reason: String

    public init(record: AppUsageRecord, category: AppUsageCategory, reason: String) {
        self.record = record
        self.category = category
        self.reason = reason
    }
}

public struct AppUsageAnalyzer {
    private let fileManager: FileManager
    private let home: URL
    private let now: @Sendable () -> Date
    private let lastUsedMetadataDate: @Sendable (URL) -> Date?

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        lastUsedMetadataDate: @escaping @Sendable (URL) -> Date? = AppUsageAnalyzer.spotlightLastUsedDate
    ) {
        self.fileManager = fileManager
        self.home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.now = now
        self.lastUsedMetadataDate = lastUsedMetadataDate
    }

    public func scanApplications(in roots: [URL]) -> [AppUsageRecord] {
        var allApps: [AppUsageRecord] = []

        for root in roots {
            collectApplications(at: root, into: &allApps)
        }

        return allApps
    }

    public func classify(_ records: [AppUsageRecord]) -> [ClassifiedAppUsage] {
        records.map { record in
            guard let lastOpenedDate = record.lastOpenedDate else {
                return ClassifiedAppUsage(
                    record: record,
                    category: .unknownUsage,
                    reason: "No reliable last-opened date is available."
                )
            }

            let days = now().timeIntervalSince(lastOpenedDate) / 86_400
            if days >= 180 {
                return ClassifiedAppUsage(
                    record: record,
                    category: .probablyUnused,
                    reason: "App has not been opened in at least 180 days."
                )
            }
            if days >= 90 {
                return ClassifiedAppUsage(
                    record: record,
                    category: .possiblyUnused,
                    reason: "App has not been opened in at least 90 days."
                )
            }
            return ClassifiedAppUsage(
                record: record,
                category: .recentlyUsed,
                reason: "App was opened recently."
            )
        }
        .sorted { $0.record.appSizeBytes > $1.record.appSizeBytes }
    }

    private func readAppRecord(at appURL: URL) -> AppUsageRecord? {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let displayName = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let version = info?["CFBundleShortVersionString"] as? String

        let values = try? appURL.resourceValues(forKeys: [.creationDateKey, .contentAccessDateKey, .contentModificationDateKey])
        let metadataLastUsedDate = lastUsedMetadataDate(appURL)
        let fallbackLastOpenedDate = values?.contentAccessDate ?? values?.contentModificationDate
        let relatedData = relatedAppData(bundleIdentifier: bundleIdentifier)
        return AppUsageRecord(
            appURL: appURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            version: version,
            appSizeBytes: directoryAllocatedSize(appURL),
            lastOpenedDate: metadataLastUsedDate ?? fallbackLastOpenedDate,
            installDate: values?.creationDate,
            relatedDataEstimateBytes: relatedData.isEmpty ? nil : relatedData.reduce(Int64(0)) { $0 + $1.sizeBytes },
            relatedData: relatedData,
            confidence: metadataLastUsedDate == nil ? .low : .medium
        )
    }

    /// Locates app support files conservatively: exact bundle-identifier match
    /// only, in the standard user Library locations. Group Containers (keyed by
    /// team identifier) and display-name matches are intentionally excluded to
    /// avoid removing data that belongs to another app.
    func relatedAppData(bundleIdentifier: String?) -> [RelatedAppData] {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            return []
        }

        let library = home.appendingPathComponent("Library", isDirectory: true)
        var results: [RelatedAppData] = []

        func append(_ url: URL, kind: String) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return
            }
            let size = isDirectory.boolValue ? directoryAllocatedSize(url) : fileAllocatedSize(url)
            results.append(RelatedAppData(url: url, sizeBytes: size, kind: kind))
        }

        // Directories named exactly by bundle identifier.
        append(library.appendingPathComponent("Application Support/\(bundleID)", isDirectory: true), kind: "Application Support")
        append(library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true), kind: "Caches")
        append(library.appendingPathComponent("Containers/\(bundleID)", isDirectory: true), kind: "Container")
        append(library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true), kind: "HTTP storage")
        append(library.appendingPathComponent("WebKit/\(bundleID)", isDirectory: true), kind: "WebKit data")
        append(library.appendingPathComponent("Logs/\(bundleID)", isDirectory: true), kind: "Logs")

        // Files named exactly by bundle identifier.
        append(library.appendingPathComponent("Preferences/\(bundleID).plist"), kind: "Preferences")
        append(library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true), kind: "Saved state")

        // Launch agents are prefixed by the bundle identifier.
        let launchAgents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
        if let entries = try? fileManager.contentsOfDirectory(
            at: launchAgents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where entry.pathExtension == "plist" && entry.lastPathComponent.hasPrefix(bundleID) {
                append(entry, kind: "Launch agent")
            }
        }

        return results
    }

    private func fileAllocatedSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private func collectApplications(at root: URL, into records: inout [AppUsageRecord]) {
        if root.pathExtension == "app" {
            if !isSystemApp(root), let record = readAppRecord(at: root) {
                records.append(record)
            }
            return
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children {
            if child.pathExtension == "app" {
                if !isSystemApp(child), let record = readAppRecord(at: child) {
                    records.append(record)
                }
                continue
            }

            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  values.isDirectory == true,
                  values.isPackage != true else {
                continue
            }

            collectApplications(at: child, into: &records)
        }
    }

    private func directoryAllocatedSize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { partial, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                return partial
            }
            return partial + Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
    }

    private func isSystemApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/System/Applications/") || path.hasPrefix("/System/")
    }

    public static func spotlightLastUsedDate(for url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else {
            return nil
        }
        return value as? Date
    }
}
