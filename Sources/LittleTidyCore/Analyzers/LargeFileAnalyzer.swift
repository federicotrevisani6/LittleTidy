import Foundation

public struct LargeFileAnalyzer: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func findLargeFiles(in files: [FileRecord], threshold: Int64 = 500_000_000) -> [LargeFileCandidate] {
        files
            .filter { $0.storageSize >= threshold }
            .filter { !isProtectedPackage($0.url) }
            .map { file in
                LargeFileCandidate(
                    file: file,
                    reason: reason(for: file, threshold: threshold),
                    score: score(file),
                    // Size identifies a review candidate, not whether it is disposable.
                    confidence: .medium
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.file.storageSize > $1.file.storageSize
                }
                return $0.score > $1.score
            }
    }

    private func reason(for file: FileRecord, threshold: Int64) -> String {
        if file.storageSize >= 5_000_000_000 {
            return "Very large file using more than 5 GB on disk."
        }
        if file.url.pathComponents.contains("Downloads") {
            return "Large file in Downloads."
        }
        return "File uses more than the on-disk threshold of \(threshold) bytes."
    }

    private func score(_ file: FileRecord) -> Int {
        var score = 0
        score += min(Int(file.storageSize / 100_000_000), 100)

        let referenceDate = now()
        if let lastAccessDate = file.lastAccessDate ?? file.modificationDate {
            let ageDays = referenceDate.timeIntervalSince(lastAccessDate) / 86_400
            score += min(max(Int(ageDays / 30), 0), 40)
        }

        if file.url.pathComponents.contains("Downloads") {
            score += 25
        }

        let ext = file.url.pathExtension.lowercased()
        if ["dmg", "pkg", "zip", "tar", "gz", "xz", "rar", "7z", "mov", "mp4", "mkv"].contains(ext) {
            score += 20
        }

        return score
    }

    private func isProtectedPackage(_ url: URL) -> Bool {
        let protectedExtensions = ["photoslibrary", "musiclibrary", "xcodeproj", "xcworkspace", "vmwarevm", "pvm"]
        return protectedExtensions.contains(url.pathExtension.lowercased())
    }
}
