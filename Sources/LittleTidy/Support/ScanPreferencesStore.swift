import Foundation

struct ScanPreferences: Equatable {
    var includeHiddenFiles: Bool
    var includeSystemFolders: Bool
    var includeCaches: Bool
    var includeRelatedAppData: Bool
    var minimumDuplicateSize: Int64
    var largeFileThreshold: Int64

    static let `default` = ScanPreferences(
        includeHiddenFiles: false,
        includeSystemFolders: false,
        includeCaches: true,
        includeRelatedAppData: false,
        minimumDuplicateSize: 1_000_000,
        largeFileThreshold: 500_000_000
    )
}

@MainActor
struct ScanPreferencesStore {
    static let shared = ScanPreferencesStore()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ScanPreferences {
        ScanPreferences(
            includeHiddenFiles: userDefaults.object(forKey: Keys.includeHiddenFiles) as? Bool ?? ScanPreferences.default.includeHiddenFiles,
            includeSystemFolders: userDefaults.object(forKey: Keys.includeSystemFolders) as? Bool ?? ScanPreferences.default.includeSystemFolders,
            includeCaches: userDefaults.object(forKey: Keys.includeCaches) as? Bool ?? ScanPreferences.default.includeCaches,
            includeRelatedAppData: userDefaults.object(forKey: Keys.includeRelatedAppData) as? Bool ?? ScanPreferences.default.includeRelatedAppData,
            minimumDuplicateSize: int64(forKey: Keys.minimumDuplicateSize, fallback: ScanPreferences.default.minimumDuplicateSize),
            largeFileThreshold: int64(forKey: Keys.largeFileThreshold, fallback: ScanPreferences.default.largeFileThreshold)
        )
    }

    func save(_ preferences: ScanPreferences) {
        userDefaults.set(preferences.includeHiddenFiles, forKey: Keys.includeHiddenFiles)
        userDefaults.set(preferences.includeSystemFolders, forKey: Keys.includeSystemFolders)
        userDefaults.set(preferences.includeCaches, forKey: Keys.includeCaches)
        userDefaults.set(preferences.includeRelatedAppData, forKey: Keys.includeRelatedAppData)
        userDefaults.set(preferences.minimumDuplicateSize, forKey: Keys.minimumDuplicateSize)
        userDefaults.set(preferences.largeFileThreshold, forKey: Keys.largeFileThreshold)
    }

    func reset() {
        save(.default)
    }

    private func int64(forKey key: String, fallback: Int64) -> Int64 {
        guard userDefaults.object(forKey: key) != nil else {
            return fallback
        }
        return Int64(userDefaults.integer(forKey: key))
    }

    private enum Keys {
        static let includeHiddenFiles = "LittleTidy.includeHiddenFiles"
        static let includeSystemFolders = "LittleTidy.includeSystemFolders"
        static let includeCaches = "LittleTidy.includeCaches"
        static let includeRelatedAppData = "LittleTidy.includeRelatedAppData"
        static let minimumDuplicateSize = "LittleTidy.minimumDuplicateSize"
        static let largeFileThreshold = "LittleTidy.largeFileThreshold"
    }
}
