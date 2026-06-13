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
    private let now: @Sendable () -> Date
    private let lastUsedMetadataDate: @Sendable (URL) -> Date?

    public init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        lastUsedMetadataDate: @escaping @Sendable (URL) -> Date? = AppUsageAnalyzer.spotlightLastUsedDate
    ) {
        self.fileManager = fileManager
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
        return AppUsageRecord(
            appURL: appURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            version: version,
            appSizeBytes: directoryAllocatedSize(appURL),
            lastOpenedDate: metadataLastUsedDate ?? fallbackLastOpenedDate,
            installDate: values?.creationDate,
            relatedDataEstimateBytes: nil,
            confidence: metadataLastUsedDate == nil ? .low : .medium
        )
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
