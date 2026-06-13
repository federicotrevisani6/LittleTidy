import Foundation

/// Aggregate disk usage of a folder, derived from the files already indexed by
/// the scan (no extra filesystem traversal).
public struct FolderUsage: Codable, Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    public let bytes: Int64
    public let fileCount: Int

    public var id: URL { url }

    public init(url: URL, name: String, bytes: Int64, fileCount: Int) {
        self.url = url
        self.name = name
        self.bytes = bytes
        self.fileCount = fileCount
    }
}

/// Buckets scanned files by the first path component beneath each scan root,
/// answering "where is my space going" without re-reading the disk.
public struct FolderUsageAnalyzer {
    public init() {}

    public func aggregate(files: [FileRecord], roots: [URL], limit: Int = 24) -> [FolderUsage] {
        let standardizedRoots = roots.map { $0.standardizedFileURL }
        var totals: [URL: (bytes: Int64, count: Int)] = [:]

        for file in files {
            guard let bucket = bucketURL(for: file.url.standardizedFileURL, roots: standardizedRoots) else {
                continue
            }
            var entry = totals[bucket] ?? (0, 0)
            entry.bytes += file.fileSize
            entry.count += 1
            totals[bucket] = entry
        }

        let usages = totals.map { url, value in
            FolderUsage(url: url, name: url.lastPathComponent, bytes: value.bytes, fileCount: value.count)
        }

        return Array(
            usages
                .sorted { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
                .prefix(limit)
        )
    }

    /// The folder a file is attributed to: the root's immediate child directory
    /// that contains it, or the root itself for files sitting directly in it.
    private func bucketURL(for fileURL: URL, roots: [URL]) -> URL? {
        for root in roots {
            let rootComponents = root.pathComponents
            let fileComponents = fileURL.pathComponents
            guard fileComponents.count > rootComponents.count,
                  Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
                continue
            }

            // File directly inside the root → attribute to the root itself.
            if fileComponents.count == rootComponents.count + 1 {
                return root
            }
            return root.appendingPathComponent(fileComponents[rootComponents.count], isDirectory: true)
        }
        return nil
    }
}
