import Foundation

/// Persists a capped, most-recent-first log of completed cleanup runs in
/// UserDefaults, mirroring the storage approach of `ScanPreferencesStore`.
@MainActor
struct CleanupHistoryStore {
    static let shared = CleanupHistoryStore()

    /// Keep the log bounded; older entries are dropped.
    static let maximumEntries = 50

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [CleanupHistoryEntry] {
        guard let data = userDefaults.data(forKey: Keys.history),
              let entries = try? JSONDecoder().decode([CleanupHistoryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Prepends a new entry and returns the updated, capped list.
    @discardableResult
    func record(_ entry: CleanupHistoryEntry) -> [CleanupHistoryEntry] {
        var entries = load()
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntries {
            entries = Array(entries.prefix(Self.maximumEntries))
        }
        persist(entries)
        return entries
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.history)
    }

    private func persist(_ entries: [CleanupHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        userDefaults.set(data, forKey: Keys.history)
    }

    private enum Keys {
        static let history = "MacCleaner.cleanupHistory"
    }
}
