import Foundation

public enum TrashPlanError: Error, Equatable {
    case emptyPlan
    case outsideApprovedRoots(URL)
    case duplicateGroupWouldRemoveAllCopies
    case systemAppBlocked(URL)
    case symbolicLinkBlocked(URL)
}

public struct TrashPlanBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func buildPlan(items: [TrashPlanItem], approvedRoots: [URL]) throws -> TrashPlan {
        guard !items.isEmpty else {
            throw TrashPlanError.emptyPlan
        }

        for item in items {
            guard isInsideApprovedRoots(item.sourceURL, approvedRoots: approvedRoots) else {
                throw TrashPlanError.outsideApprovedRoots(item.sourceURL)
            }
            if item.sourceURL.pathExtension == "app", isSystemApp(item.sourceURL) {
                throw TrashPlanError.systemAppBlocked(item.sourceURL)
            }
            if isSymbolicLink(item.sourceURL) {
                throw TrashPlanError.symbolicLinkBlocked(item.sourceURL)
            }
        }

        return TrashPlan(items: items)
    }

    public func buildDuplicatePlan(group: DuplicateGroup, removing selectedFiles: [FileRecord], approvedRoots: [URL]) throws -> TrashPlan {
        let selectedIDs = Set(selectedFiles.map(\.id))
        let groupIDs = Set(group.files.map(\.id))

        if selectedIDs == groupIDs {
            throw TrashPlanError.duplicateGroupWouldRemoveAllCopies
        }

        let items = selectedFiles.map {
            TrashPlanItem(
                sourceURL: $0.url,
                bytes: $0.fileSize,
                category: .duplicate,
                reason: "Duplicate file with matching SHA-256 hash."
            )
        }
        return try buildPlan(items: items, approvedRoots: approvedRoots)
    }

    private func isInsideApprovedRoots(_ url: URL, approvedRoots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return approvedRoots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private func isSystemApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/System/Applications/") || path.hasPrefix("/System/")
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
