import Foundation

public final class FileInventoryScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let scanner = self
            let cancellation = CancellationState()

            DispatchQueue.global(qos: .userInitiated).async {
                continuation.yield(.started(rootCount: request.roots.count))

                var scannedFiles = 0
                var scannedBytes: Int64 = 0
                var skippedItems = 0
                var permissionErrors = 0

                for (rootOffset, root) in request.roots.enumerated() {
                    if cancellation.isCancelled {
                        break
                    }

                    let rootIndex = rootOffset + 1
                    continuation.yield(.rootStarted(url: root, index: rootIndex, total: request.roots.count))
                    scanner.yieldProgress(
                        continuation,
                        currentRoot: root,
                        rootIndex: rootIndex,
                        rootCount: request.roots.count,
                        scannedFiles: scannedFiles,
                        scannedBytes: scannedBytes,
                        skippedItems: skippedItems,
                        permissionErrors: permissionErrors
                    )

                    guard scanner.isAllowedRoot(root, options: request.options) else {
                        skippedItems += 1
                        continuation.yield(.skipped(root, reason: "System folders are excluded by default."))
                        scanner.yieldProgress(
                            continuation,
                            currentRoot: root,
                            rootIndex: rootIndex,
                            rootCount: request.roots.count,
                            scannedFiles: scannedFiles,
                            scannedBytes: scannedBytes,
                            skippedItems: skippedItems,
                            permissionErrors: permissionErrors
                        )
                        continue
                    }

                    guard let enumerator = scanner.fileManager.enumerator(
                        at: root,
                        includingPropertiesForKeys: FileInventoryScanner.resourceKeys,
                        options: [.skipsPackageDescendants],
                        errorHandler: { url, error in
                            permissionErrors += 1
                            continuation.yield(.permissionDenied(url, error))
                            return true
                        }
                    ) else {
                        skippedItems += 1
                        continuation.yield(.skipped(root, reason: "Could not enumerate folder."))
                        scanner.yieldProgress(
                            continuation,
                            currentRoot: root,
                            rootIndex: rootIndex,
                            rootCount: request.roots.count,
                            scannedFiles: scannedFiles,
                            scannedBytes: scannedBytes,
                            skippedItems: skippedItems,
                            permissionErrors: permissionErrors
                        )
                        continue
                    }

                    for case let fileURL as URL in enumerator {
                        if cancellation.isCancelled {
                            break
                        }

                        do {
                            let values = try fileURL.resourceValues(forKeys: Set(Self.resourceKeys))

                            if values.isDirectory == true {
                                if scanner.shouldSkipDirectory(fileURL, values: values, options: request.options) {
                                    enumerator.skipDescendants()
                                    skippedItems += 1
                                    continuation.yield(.skipped(fileURL, reason: "Directory is excluded by scan options."))
                                }
                                continue
                            }

                            guard values.isRegularFile == true else {
                                skippedItems += 1
                                continuation.yield(.skipped(fileURL, reason: "Only regular files are indexed."))
                                continue
                            }

                            if scanner.shouldSkipFile(fileURL, values: values, options: request.options) {
                                skippedItems += 1
                                continuation.yield(.skipped(fileURL, reason: "File is excluded by scan options."))
                                continue
                            }

                            let record = FileRecord(
                                url: fileURL,
                                fileSize: Int64(values.fileSize ?? 0),
                                allocatedSize: values.totalFileAllocatedSize.map(Int64.init),
                                creationDate: values.creationDate,
                                modificationDate: values.contentModificationDate,
                                lastAccessDate: values.contentAccessDate,
                                contentType: values.typeIdentifier,
                                isHidden: values.isHidden ?? fileURL.lastPathComponent.hasPrefix("."),
                                volumeIdentifier: values.volumeIdentifier?.description
                            )

                            scannedFiles += 1
                            scannedBytes += record.fileSize
                            continuation.yield(.indexedFile(record))

                            if scannedFiles.isMultiple(of: 100) {
                                scanner.yieldProgress(
                                    continuation,
                                    currentRoot: root,
                                    rootIndex: rootIndex,
                                    rootCount: request.roots.count,
                                    scannedFiles: scannedFiles,
                                    scannedBytes: scannedBytes,
                                    skippedItems: skippedItems,
                                    permissionErrors: permissionErrors
                                )
                            }
                        } catch {
                            permissionErrors += 1
                            continuation.yield(.permissionDenied(fileURL, error))
                        }
                    }
                }

                scanner.yieldProgress(
                    continuation,
                    currentRoot: nil,
                    rootIndex: request.roots.count,
                    rootCount: request.roots.count,
                    scannedFiles: scannedFiles,
                    scannedBytes: scannedBytes,
                    skippedItems: skippedItems,
                    permissionErrors: permissionErrors
                )
                continuation.yield(.completed(ScanSummary(
                    scannedFiles: scannedFiles,
                    scannedBytes: scannedBytes,
                    skippedItems: skippedItems,
                    permissionErrors: permissionErrors
                )))
                continuation.finish()
            }

            continuation.onTermination = { _ in cancellation.cancel() }
        }
    }

    private func yieldProgress(
        _ continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation,
        currentRoot: URL?,
        rootIndex: Int,
        rootCount: Int,
        scannedFiles: Int,
        scannedBytes: Int64,
        skippedItems: Int,
        permissionErrors: Int
    ) {
        continuation.yield(.progress(ScanProgress(
            currentRoot: currentRoot,
            rootIndex: rootIndex,
            rootCount: rootCount,
            scannedFiles: scannedFiles,
            scannedBytes: scannedBytes,
            skippedItems: skippedItems,
            permissionErrors: permissionErrors
        )))
    }

    private func shouldSkipDirectory(_ url: URL, values: URLResourceValues, options: ScanOptions) -> Bool {
        if !options.includeHiddenFiles, values.isHidden == true || url.lastPathComponent.hasPrefix(".") {
            return true
        }
        if !options.followSymbolicLinks, isSymbolicLink(url) {
            return true
        }
        return false
    }

    private func shouldSkipFile(_ url: URL, values: URLResourceValues, options: ScanOptions) -> Bool {
        if !options.includeHiddenFiles, values.isHidden == true || url.lastPathComponent.hasPrefix(".") {
            return true
        }
        if !options.followSymbolicLinks, isSymbolicLink(url) {
            return true
        }
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
            return true
        }
        return false
    }

    private func isAllowedRoot(_ url: URL, options: ScanOptions) -> Bool {
        guard !options.includeSystemFolders else {
            return true
        }

        let path = url.standardizedFileURL.path
        let blockedPrefixes = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin"]
        return !blockedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isHiddenKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .typeIdentifierKey,
        .volumeIdentifierKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .isSymbolicLinkKey
    ]
}

private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }
}
