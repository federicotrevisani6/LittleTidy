import Foundation

public struct CleanupAnalysisResult: Sendable {
    public let duplicateGroups: [DuplicateGroup]
    public let largeFiles: [LargeFileCandidate]
    public let unusedApps: [ClassifiedAppUsage]

    public init(
        duplicateGroups: [DuplicateGroup],
        largeFiles: [LargeFileCandidate],
        unusedApps: [ClassifiedAppUsage]
    ) {
        self.duplicateGroups = duplicateGroups
        self.largeFiles = largeFiles
        self.unusedApps = unusedApps
    }
}

public struct CleanupAnalysis {
    private let duplicateAnalyzer: DuplicateAnalyzer
    private let largeFileAnalyzer: LargeFileAnalyzer
    private let appUsageAnalyzer: AppUsageAnalyzer

    public init(
        duplicateAnalyzer: DuplicateAnalyzer = DuplicateAnalyzer(),
        largeFileAnalyzer: LargeFileAnalyzer = LargeFileAnalyzer(),
        appUsageAnalyzer: AppUsageAnalyzer = AppUsageAnalyzer()
    ) {
        self.duplicateAnalyzer = duplicateAnalyzer
        self.largeFileAnalyzer = largeFileAnalyzer
        self.appUsageAnalyzer = appUsageAnalyzer
    }

    public func analyze(files: [FileRecord], options: ScanOptions, appRoots: [URL]) throws -> CleanupAnalysisResult {
        let duplicates = try duplicateAnalyzer.findDuplicates(
            in: files,
            minimumSize: options.minimumDuplicateSize
        )
        let largeFiles = largeFileAnalyzer.findLargeFiles(
            in: files,
            threshold: options.largeFileThreshold
        )
        let apps = appUsageAnalyzer
            .classify(appUsageAnalyzer.scanApplications(in: appRoots))
            .filter { $0.category != .recentlyUsed }

        return CleanupAnalysisResult(
            duplicateGroups: duplicates,
            largeFiles: largeFiles,
            unusedApps: apps
        )
    }
}
