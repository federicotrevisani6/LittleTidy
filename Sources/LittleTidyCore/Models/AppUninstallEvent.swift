import Foundation

public struct AppUninstallEvent: Identifiable, Codable, Sendable, Hashable {
    public var id: String { bundleIdentifier }
    public let appURL: URL
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String?
    public let appSizeBytes: Int64
    public let leftovers: [RelatedAppData]
    public let totalLeftoverBytes: Int64
    public let detectedAt: Date

    public init(
        appURL: URL,
        bundleIdentifier: String,
        displayName: String,
        version: String?,
        appSizeBytes: Int64,
        leftovers: [RelatedAppData],
        detectedAt: Date = Date()
    ) {
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.appSizeBytes = appSizeBytes
        self.leftovers = leftovers
        self.totalLeftoverBytes = leftovers.reduce(0) { $0 + $1.sizeBytes }
        self.detectedAt = detectedAt
    }
}
