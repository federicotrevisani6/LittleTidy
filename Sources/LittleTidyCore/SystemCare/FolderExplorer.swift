import Foundation

public enum StorageContentKind: String, Codable, Sendable {
    case cache, buildOutput, gitRepository, gitWorktree, appData, file, unclassified, protected
    public var title: String {
        switch self {
        case .cache: "Cache"
        case .buildOutput: "Build output"
        case .gitRepository: "Git repository"
        case .gitWorktree: "Git worktree"
        case .appData: "Application or personal data"
        case .file: "File"
        case .unclassified: "Needs review"
        case .protected: "Protected"
        }
    }
    public var explanation: String {
        switch self {
        case .cache: "Located in a known cache folder. Review selected entries in Application Caches."
        case .buildOutput: "Recognized build data. Stop the owning build and review it in Developer Storage."
        case .gitRepository, .gitWorktree: "May contain uncommitted work. Changes and activity have not been checked; review in your Git client before removing anything."
        case .appData: "May contain documents, databases, settings, or shared app data. Manage it through the owning app."
        case .file: "Size describes this file, not whether it is safe to remove."
        case .unclassified: "Ownership and cleanup safety have not been established."
        case .protected: "Links, device mounts, and application packages are not explored."
        }
    }
}

public struct StorageFolderEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let kind: StorageContentKind
    public let canExplore: Bool
    public var bytes: Int64?
    public var issue: String?
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct StorageFolderListing: Sendable {
    public let entries: [StorageFolderEntry]
    public let isTruncated: Bool
}

/// One-level, read-only exploration. It never executes repository code, checks
/// out a branch, follows a symbolic link, or exposes arbitrary paths to root XPC.
public actor FolderExplorer {
    private let roots: [URL]
    private let home: URL
    private let analyzer: SystemCareAnalyzer
    private let fm = FileManager.default
    public init(allowedRoots: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser,
                runner: any DeveloperToolCommandRunning = BoundedCommandRunner(timeout: 5)) {
        roots = allowedRoots.map(\.standardizedFileURL)
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        analyzer = SystemCareAnalyzer(home: home, runner: runner)
    }
    public func list(at directory: URL) throws -> StorageFolderListing {
        try validate(directory)
        var accessError: Error?
        guard let iterator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in accessError = error; return false }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var entries: [StorageFolderEntry] = []
        for case let child as URL in iterator {
            try Task.checkCancellation()
            if entries.count == 250 { return .init(entries: entries, isTruncated: true) }
            let attributes = try fm.attributesOfItem(atPath: child.path)
            let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
            let link = attributes[.type] as? FileAttributeType == .typeSymbolicLink
            let mount = child.pathComponents.contains("CoreDevice")
            let package = ["app", "framework", "bundle", "photoslibrary", "xcodeproj", "xcworkspace"].contains(child.pathExtension.lowercased())
            let kind: StorageContentKind = link || mount || package ? .protected : classify(child, isDirectory: isDirectory)
            entries.append(.init(path: child.path, kind: kind, canExplore: isDirectory && !link && !mount && !package,
                                 bytes: nil, issue: link || mount ? "Excluded from measurement and traversal." : nil))
        }
        if let accessError { throw accessError }
        return .init(entries: entries, isTruncated: false)
    }
    public func measure(_ entry: StorageFolderEntry) async throws -> StorageFolderEntry {
        if entry.issue != nil { return entry }
        try validate(URL(fileURLWithPath: entry.path), allowPackage: true)
        let measurement = try await analyzer.storage(locations: [.init(name: entry.name, path: entry.path, explanation: entry.kind.explanation)]).first
        var result = entry
        result.bytes = measurement?.bytes
        result.issue = measurement?.issue ?? (measurement == nil ? "Item disappeared during measurement." : nil)
        return result
    }
    private func validate(_ url: URL, allowPackage: Bool = false) throws {
        let candidate = url.standardizedFileURL
        guard let root = roots.first(where: { candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/") }),
              !candidate.pathComponents.contains("CoreDevice") else { throw CocoaError(.fileReadNoPermission) }
        var cursor = root
        let parts = candidate.pathComponents.dropFirst(root.pathComponents.count)
        for component in [""] + Array(parts) {
            if !component.isEmpty { cursor.appendPathComponent(component) }
            let attributes = try fm.attributesOfItem(atPath: cursor.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw CocoaError(.fileReadNoPermission) }
        }
        let resolved = candidate.resolvingSymlinksInPath().path
        let base = root.resolvingSymlinksInPath().path
        guard resolved == base || resolved.hasPrefix(base + "/") else { throw CocoaError(.fileReadNoPermission) }
        if !allowPackage && ["app", "framework", "bundle", "photoslibrary", "xcodeproj", "xcworkspace"].contains(candidate.pathExtension.lowercased()) {
            throw CocoaError(.fileReadNoPermission)
        }
    }
    private func classify(_ url: URL, isDirectory: Bool) -> StorageContentKind {
        guard isDirectory else { return .file }
        let marker = url.appendingPathComponent(".git")
        if let type = (try? fm.attributesOfItem(atPath: marker.path))?[.type] as? FileAttributeType {
            if type == .typeDirectory { return .gitRepository }
            if type == .typeRegular, let handle = try? FileHandle(forReadingFrom: marker) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 4096), String(decoding: data, as: UTF8.self).hasPrefix("gitdir: ") { return .gitWorktree }
            }
        }
        if url.lastPathComponent == ".build", regularFile(url.deletingLastPathComponent().appendingPathComponent("Package.swift")) { return .buildOutput }
        let info = url.appendingPathComponent("info.plist")
        if regularFile(info), fm.fileExists(atPath: url.appendingPathComponent("Build").path),
           let data = readMetadata(info),
           let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any], plist["WorkspacePath"] is String { return .buildOutput }
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let cache = home.appendingPathComponent("Library/Caches").path
        if candidatePath == cache || candidatePath.hasPrefix(cache + "/") { return .cache }
        let containerBase = home.appendingPathComponent("Library/Containers").path + "/"
        if candidatePath.hasPrefix(containerBase) {
            let parts = candidatePath.dropFirst(containerBase.count).split(separator: "/")
            if parts.count >= 4 && parts[1] == "Data" && parts[2] == "Library" && parts[3] == "Caches" { return .cache }
        }
        for relative in ["Library/Containers", "Library/Group Containers", "Library/Application Support", "Library/Mail", "Library/Messages"] {
            let base = home.appendingPathComponent(relative).path
            if candidatePath == base || candidatePath.hasPrefix(base + "/") { return .appData }
        }
        return .unclassified
    }
    private func readMetadata(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65537), data.count <= 65536 else { return nil }
        return data
    }
    private func regularFile(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular
    }
}
