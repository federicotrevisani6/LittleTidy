import Foundation

@MainActor
struct FolderBookmarkStore {
    static let shared = FolderBookmarkStore()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func restoredScanRoots(fallback: [URL]) -> [URL] {
        restoredURLs(forKey: Keys.scanRoots, fallback: fallback)
    }

    func restoredAppRoots(fallback: [URL]) -> [URL] {
        restoredURLs(forKey: Keys.appRoots, fallback: fallback)
    }

    func saveScanRoots(_ urls: [URL]) {
        save(urls, forKey: Keys.scanRoots)
    }

    func saveAppRoots(_ urls: [URL]) {
        save(urls, forKey: Keys.appRoots)
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.scanRoots)
        userDefaults.removeObject(forKey: Keys.appRoots)
    }

    private func restoredURLs(forKey key: String, fallback: [URL]) -> [URL] {
        guard let bookmarkData = userDefaults.array(forKey: key) as? [Data],
              !bookmarkData.isEmpty else {
            return fallback
        }

        let urls = bookmarkData.compactMap { data -> URL? in
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return isStale ? nil : url
            } catch {
                return nil
            }
        }

        return urls.isEmpty ? fallback : Self.unique(urls)
    }

    private func save(_ urls: [URL], forKey key: String) {
        let bookmarkData = Self.unique(urls).compactMap { url -> Data? in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        userDefaults.set(bookmarkData, forKey: key)
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private enum Keys {
        static let scanRoots = "LittleTidy.scanRootBookmarks"
        static let appRoots = "LittleTidy.appRootBookmarks"
    }
}

final class SecurityScopedFolderAccess: @unchecked Sendable {
    private var accessedURLs: [URL] = []

    init(urls: [URL]) {
        accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    deinit {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
