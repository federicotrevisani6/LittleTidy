import CryptoKit
import Foundation

public enum DuplicateKeepStrategy: String, Codable, CaseIterable, Sendable {
    case smart
    case oldest
    case newest
    case preferNonDownloads
    case shortestPath

    public var title: String {
        switch self {
        case .smart: "Smart (Recommended)"
        case .oldest: "Keep Oldest File"
        case .newest: "Keep Newest File"
        case .preferNonDownloads: "Prefer Main Folders (Avoid Downloads)"
        case .shortestPath: "Keep Shortest Path"
        }
    }
}

public struct DuplicateAnalyzer: Sendable {
    public init() {}

    public func findDuplicates(
        in files: [FileRecord],
        minimumSize: Int64 = 1_000_000,
        strategy: DuplicateKeepStrategy = .smart
    ) throws -> [DuplicateGroup] {
        let sizeGroups = Dictionary(grouping: files.filter { $0.fileSize >= minimumSize }, by: \.fileSize)
            .values
            .filter { $0.count > 1 }

        var groups: [DuplicateGroup] = []

        for sizeGroup in sizeGroups {
            try Task.checkCancellation()

            let quickGroups = Dictionary(grouping: try sizeGroup.compactMap { file -> (FileRecord, String)? in
                try Task.checkCancellation()
                guard let fingerprint = try? quickFingerprint(for: file.url, fileSize: file.fileSize) else { return nil }
                return (file, fingerprint)
            }, by: \.1)

            for quickGroup in quickGroups.values where quickGroup.count > 1 {
                try Task.checkCancellation()

                let hashGroups = Dictionary(grouping: try quickGroup.compactMap { file, _ -> (FileRecord, String)? in
                    try Task.checkCancellation()
                    do {
                        return (file, try fullHash(for: file.url))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return nil
                    }
                }, by: \.1)

                for (hash, matchingFiles) in hashGroups where matchingFiles.count > 1 {
                    let duplicateFiles = matchingFiles.map(\.0).sorted { $0.url.path < $1.url.path }
                    let recommendedKeep = chooseRecommendedKeep(from: duplicateFiles, strategy: strategy)
                    let reclaimableBytes = duplicateFiles
                        .filter { $0.id != recommendedKeep?.id }
                        .reduce(Int64(0)) { $0 + $1.fileSize }

                    groups.append(DuplicateGroup(
                        contentHash: hash,
                        files: duplicateFiles,
                        reclaimableBytes: reclaimableBytes,
                        confidence: .high,
                        recommendedKeep: recommendedKeep
                    ))
                }
            }
        }

        return groups.sorted {
            if $0.reclaimableBytes == $1.reclaimableBytes {
                return $0.files.first?.url.path ?? "" < $1.files.first?.url.path ?? ""
            }
            return $0.reclaimableBytes > $1.reclaimableBytes
        }
    }

    public func chooseRecommendedKeep(from files: [FileRecord], strategy: DuplicateKeepStrategy = .smart) -> FileRecord? {
        switch strategy {
        case .smart:
            return files.min { lhs, rhs in
                let lhsScore = keepScore(lhs)
                let rhsScore = keepScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.url.path < rhs.url.path
                }
                return lhsScore < rhsScore
            }
        case .oldest:
            return files.min { lhs, rhs in
                let lhsDate = lhs.creationDate ?? lhs.modificationDate ?? .distantFuture
                let rhsDate = rhs.creationDate ?? rhs.modificationDate ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.url.path < rhs.url.path
                }
                return lhsDate < rhsDate
            }
        case .newest:
            return files.min { lhs, rhs in
                let lhsDate = lhs.modificationDate ?? lhs.creationDate ?? .distantPast
                let rhsDate = rhs.modificationDate ?? rhs.creationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.url.path < rhs.url.path
                }
                return lhsDate > rhsDate
            }
        case .preferNonDownloads:
            return files.min { lhs, rhs in
                let lhsInDownloads = lhs.url.pathComponents.contains("Downloads")
                let rhsInDownloads = rhs.url.pathComponents.contains("Downloads")
                if lhsInDownloads != rhsInDownloads {
                    return !lhsInDownloads && rhsInDownloads
                }
                if lhs.url.path.count == rhs.url.path.count {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.url.path.count < rhs.url.path.count
            }
        case .shortestPath:
            return files.min { lhs, rhs in
                if lhs.url.path.count == rhs.url.path.count {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.url.path.count < rhs.url.path.count
            }
        }
    }

    private func keepScore(_ file: FileRecord) -> Int {
        var score = 0
        let pathComponents = file.url.standardizedFileURL.pathComponents

        if pathComponents.contains("Downloads") {
            score += 100
        }
        if file.isHidden {
            score += 50
        }
        score += min(pathComponents.count, 40)

        if let creationDate = file.creationDate {
            score += Int(creationDate.timeIntervalSince1970 / 86_400 / 365)
        }

        return score
    }

    private func quickFingerprint(for url: URL, fileSize: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize = UInt64(64 * 1024)
        let offsets: [UInt64] = [
            0,
            UInt64(max(0, fileSize / 2 - Int64(chunkSize / 2))),
            UInt64(max(0, fileSize - Int64(chunkSize)))
        ]

        var hasher = SHA256()
        for offset in offsets {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: Int(chunkSize)) ?? Data()
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func fullHash(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
