import Foundation

/// iOS and iPadOS device backups kept by Finder and Apple Devices. Each one is
/// a copy of a person's phone, so every backup is `review`, never preselected.
/// Only `Info.plist` and `Manifest.plist` are read, never the backup contents.
public struct IOSBackupAnalyzer: Sendable {
    private let backupRoot: URL

    public init(
        backupRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
    ) {
        self.backupRoot = backupRoot
    }

    public func analyze() throws -> [EverydaySpaceItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupRoot.path) else { return [] }
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw EverydayAccessError.needsAccess
        }

        struct Backup {
            let url: URL
            let deviceName: String?
            let product: String?
            let version: String?
            let date: Date?
            let encrypted: Bool
        }

        var backups: [Backup] = []
        for url in children {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let info = Self.readPlist(url.appendingPathComponent("Info.plist"))
            let manifest = Self.readPlist(url.appendingPathComponent("Manifest.plist"))
            backups.append(Backup(
                url: url,
                deviceName: info?["Device Name"] as? String,
                product: info?["Product Type"] as? String ?? info?["Product Name"] as? String,
                version: info?["Product Version"] as? String,
                date: info?["Last Backup Date"] as? Date,
                encrypted: manifest?["IsEncrypted"] as? Bool ?? false
            ))
        }

        // The newest backup of each device name gets the stronger warning.
        var newest: [String: Date] = [:]
        for backup in backups {
            guard let name = backup.deviceName, let date = backup.date else { continue }
            if newest[name].map({ date > $0 }) ?? true { newest[name] = date }
        }

        return backups.map { backup in
            let bytes = FileSizing.allocatedBytes(at: backup.url)
            guard let name = backup.deviceName else {
                return EverydaySpaceItem(
                    kind: .iosBackups,
                    name: backup.url.lastPathComponent,
                    detail: "Not a recognisable backup",
                    url: backup.url,
                    bytes: bytes,
                    tier: .unclassified,
                    reason: "This folder has no readable Info.plist, so LittleTidy cannot tell what it is.",
                    consequence: "LittleTidy does not remove it."
                )
            }
            let isNewest = backup.date.flatMap { newest[name] == $0 } ?? false
            var detailParts = [backup.version.map { "iOS \($0)" }, backup.date.map { "backed up \($0.formatted(date: .abbreviated, time: .omitted))" }]
                .compactMap { $0 }
            if backup.encrypted { detailParts.append("encrypted") }
            var warnings: [String] = []
            if isNewest { warnings.append("This is the most recent backup of this device.") }
            if backup.encrypted {
                warnings.append("Encrypted. Deleting it removes your only way to restore from it unless you have another backup.")
            }
            return EverydaySpaceItem(
                kind: .iosBackups,
                name: name,
                detail: detailParts.joined(separator: " · "),
                url: backup.url,
                bytes: bytes,
                tier: .review,
                reason: "A backup of \"\(name)\" kept on this Mac.",
                consequence: "This is a copy of your iPhone or iPad data. If the device is lost or broken and no other backup exists, this data cannot be recovered. The Trash keeps it until you empty it.",
                warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
