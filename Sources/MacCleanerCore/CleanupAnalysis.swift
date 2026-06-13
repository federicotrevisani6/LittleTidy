import Foundation

public struct CleanupAnalysisResult: Sendable {
    public let duplicateGroups: [DuplicateGroup]
    public let largeFiles: [LargeFileCandidate]
    public let unusedApps: [ClassifiedAppUsage]
    public let caches: [CacheCandidate]

    public init(
        duplicateGroups: [DuplicateGroup],
        largeFiles: [LargeFileCandidate],
        unusedApps: [ClassifiedAppUsage],
        caches: [CacheCandidate] = []
    ) {
        self.duplicateGroups = duplicateGroups
        self.largeFiles = largeFiles
        self.unusedApps = unusedApps
        self.caches = caches
    }
}

public struct CleanupAnalysis {
    private let duplicateAnalyzer: DuplicateAnalyzer
    private let largeFileAnalyzer: LargeFileAnalyzer
    private let appUsageAnalyzer: AppUsageAnalyzer
    private let cacheAnalyzer: CacheAnalyzer

    public init(
        duplicateAnalyzer: DuplicateAnalyzer = DuplicateAnalyzer(),
        largeFileAnalyzer: LargeFileAnalyzer = LargeFileAnalyzer(),
        appUsageAnalyzer: AppUsageAnalyzer = AppUsageAnalyzer(),
        cacheAnalyzer: CacheAnalyzer = CacheAnalyzer()
    ) {
        self.duplicateAnalyzer = duplicateAnalyzer
        self.largeFileAnalyzer = largeFileAnalyzer
        self.appUsageAnalyzer = appUsageAnalyzer
        self.cacheAnalyzer = cacheAnalyzer
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
        let caches = options.includeCaches ? try cacheAnalyzer.findCaches() : []

        return CleanupAnalysisResult(
            duplicateGroups: duplicates,
            largeFiles: largeFiles,
            unusedApps: apps,
            caches: caches
        )
    }
}
