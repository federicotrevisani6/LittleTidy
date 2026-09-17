import Foundation

public struct CleanupAnalysisResult: Sendable {
    public let duplicateGroups: [DuplicateGroup]
    public let largeFiles: [LargeFileCandidate]
    public let unusedApps: [ClassifiedAppUsage]
    public let caches: [CacheCandidate]
    public let folderUsage: [FolderUsage]

    public init(
        duplicateGroups: [DuplicateGroup],
        largeFiles: [LargeFileCandidate],
        unusedApps: [ClassifiedAppUsage],
        caches: [CacheCandidate] = [],
        folderUsage: [FolderUsage] = []
    ) {
        self.duplicateGroups = duplicateGroups
        self.largeFiles = largeFiles
        self.unusedApps = unusedApps
        self.caches = caches
        self.folderUsage = folderUsage
    }
}

public struct CleanupAnalysis {
    private let duplicateAnalyzer: DuplicateAnalyzer
    private let largeFileAnalyzer: LargeFileAnalyzer
    private let appUsageAnalyzer: AppUsageAnalyzer
    private let cacheAnalyzer: CacheAnalyzer
    private let folderUsageAnalyzer: FolderUsageAnalyzer

    public init(
        duplicateAnalyzer: DuplicateAnalyzer = DuplicateAnalyzer(),
        largeFileAnalyzer: LargeFileAnalyzer = LargeFileAnalyzer(),
        appUsageAnalyzer: AppUsageAnalyzer = AppUsageAnalyzer(),
        cacheAnalyzer: CacheAnalyzer = CacheAnalyzer(),
        folderUsageAnalyzer: FolderUsageAnalyzer = FolderUsageAnalyzer()
    ) {
        self.duplicateAnalyzer = duplicateAnalyzer
        self.largeFileAnalyzer = largeFileAnalyzer
        self.appUsageAnalyzer = appUsageAnalyzer
        self.cacheAnalyzer = cacheAnalyzer
        self.folderUsageAnalyzer = folderUsageAnalyzer
    }

    public func analyze(files: [FileRecord], options: ScanOptions, appRoots: [URL], scanRoots: [URL] = []) async throws -> CleanupAnalysisResult {
        let duplicateAnalyzer = self.duplicateAnalyzer
        let largeFileAnalyzer = self.largeFileAnalyzer
        let folderUsageAnalyzer = self.folderUsageAnalyzer

        async let duplicates = try duplicateAnalyzer.findDuplicates(
            in: files,
            minimumSize: options.minimumDuplicateSize
        )
        async let largeFiles = largeFileAnalyzer.findLargeFiles(
            in: files,
            threshold: options.largeFileThreshold
        )
        let apps = appUsageAnalyzer
            .classify(appUsageAnalyzer.scanApplications(in: appRoots))
            .filter { $0.category != .recentlyUsed }
        let caches = options.includeCaches ? try cacheAnalyzer.findCaches() : []
        async let folderUsage = folderUsageAnalyzer.aggregate(files: files, roots: scanRoots)

        let resolved = try await (duplicates, largeFiles, folderUsage)

        return CleanupAnalysisResult(
            duplicateGroups: resolved.0,
            largeFiles: resolved.1,
            unusedApps: apps,
            caches: caches,
            folderUsage: resolved.2
        )
    }
}
