import Foundation

public struct LargeFileAnalyzer: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func findLargeFiles(in files: [FileRecord], threshold: Int64 = 500_000_000) -> [LargeFileCandidate] {
        files
            .filter { $0.fileSize >= threshold }
            .filter { !isProtectedPackage($0.url) }
            .map { file in
                LargeFileCandidate(
                    file: file,
                    reason: reason(for: file, threshold: threshold),
                    score: score(file),
                    confidence: .high
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.file.fileSize > $1.file.fileSize
                }
                return $0.score > $1.score
            }
    }

    private func reason(for file: FileRecord, threshold: Int64) -> String {
        if file.fileSize >= 5_000_000_000 {
            return "Very large file above 5 GB."
        }
        if file.url.pathComponents.contains("Downloads") {
            return "Large file in Downloads."
        }
        return "File is above the large-file threshold of \(threshold) bytes."
    }

    private func score(_ file: FileRecord) -> Int {
        var score = 0
        score += min(Int(file.fileSize / 100_000_000), 100)

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
