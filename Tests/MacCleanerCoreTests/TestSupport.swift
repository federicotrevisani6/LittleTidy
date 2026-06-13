import Foundation
@testable import MacCleanerCore

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

func record(for url: URL) throws -> FileRecord {
    let values = try url.resourceValues(forKeys: [
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .typeIdentifierKey,
        .isHiddenKey,
        .volumeIdentifierKey
    ])

    return FileRecord(
        url: url,
        fileSize: Int64(values.fileSize ?? 0),
        allocatedSize: values.totalFileAllocatedSize.map(Int64.init),
        creationDate: values.creationDate,
        modificationDate: values.contentModificationDate,
        lastAccessDate: values.contentAccessDate,
        contentType: values.typeIdentifier,
        isHidden: values.isHidden ?? false,
        volumeIdentifier: values.volumeIdentifier?.description
    )
}
