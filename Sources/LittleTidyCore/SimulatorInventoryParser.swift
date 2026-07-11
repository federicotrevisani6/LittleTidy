import Foundation

public struct SimulatorDeviceRecord: Equatable, Sendable {
    public let udid: String
    public let name: String
    public let state: String
    public let runtimeIdentifier: String
    public let isAvailable: Bool
    public let dataPath: String?
}

public struct SimulatorRuntimeRecord: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let isAvailable: Bool
    public let bundlePath: String?
}

public struct SimulatorInventory: Equatable, Sendable {
    public let devices: [SimulatorDeviceRecord]
    public let runtimes: [SimulatorRuntimeRecord]
}

public struct SimulatorRuntimeDiskImageRecord: Equatable, Sendable {
    public let identifier: String
    public let runtimeIdentifier: String
    public let version: String
    public let build: String
    public let sizeBytes: Int64
    public let lastUsedAt: Date?
    public let isDeletable: Bool
    public let state: String
    public let runtimeBundlePath: String?
}

public enum SimulatorInventoryParserError: Error, Equatable {
    case invalidJSON
}

public struct SimulatorInventoryParser {
    public init() {}

    public func parse(_ data: Data) throws -> SimulatorInventory {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimulatorInventoryParserError.invalidJSON
        }

        let runtimeRecords = (root["runtimes"] as? [[String: Any]] ?? []).compactMap(parseRuntime)
        var devices: [SimulatorDeviceRecord] = []
        for (runtimeIdentifier, values) in root["devices"] as? [String: [[String: Any]]] ?? [:] {
            devices.append(contentsOf: values.compactMap { parseDevice($0, runtimeIdentifier: runtimeIdentifier) })
        }

        return SimulatorInventory(
            devices: devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            runtimes: runtimeRecords.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    public func parseRuntimeDiskImages(_ data: Data) throws -> [SimulatorRuntimeDiskImageRecord] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimulatorInventoryParserError.invalidJSON
        }
        let formatter = ISO8601DateFormatter()
        return root.compactMap { key, rawValue in
            guard let value = rawValue as? [String: Any],
                  let runtimeIdentifier = value["runtimeIdentifier"] as? String,
                  let sizeNumber = value["sizeBytes"] as? NSNumber else {
                return nil
            }
            return SimulatorRuntimeDiskImageRecord(
                identifier: value["identifier"] as? String ?? key,
                runtimeIdentifier: runtimeIdentifier,
                version: value["version"] as? String ?? "Unknown version",
                build: value["build"] as? String ?? "Unknown build",
                sizeBytes: sizeNumber.int64Value,
                lastUsedAt: (value["lastUsedAt"] as? String).flatMap(formatter.date),
                isDeletable: value["deletable"] as? Bool ?? false,
                state: value["state"] as? String ?? "Unknown",
                runtimeBundlePath: value["runtimeBundlePath"] as? String
            )
        }
        .sorted { $0.runtimeIdentifier < $1.runtimeIdentifier }
    }

    private func parseDevice(_ value: [String: Any], runtimeIdentifier: String) -> SimulatorDeviceRecord? {
        guard let udid = value["udid"] as? String,
              let name = value["name"] as? String,
              let state = value["state"] as? String else {
            return nil
        }
        return SimulatorDeviceRecord(
            udid: udid,
            name: name,
            state: state,
            runtimeIdentifier: runtimeIdentifier,
            isAvailable: availability(from: value),
            dataPath: value["dataPath"] as? String
        )
    }

    private func parseRuntime(_ value: [String: Any]) -> SimulatorRuntimeRecord? {
        guard let identifier = value["identifier"] as? String,
              let name = value["name"] as? String else {
            return nil
        }
        return SimulatorRuntimeRecord(
            identifier: identifier,
            name: name,
            version: value["version"] as? String ?? "Unknown version",
            isAvailable: availability(from: value),
            bundlePath: value["bundlePath"] as? String
        )
    }

    private func availability(from value: [String: Any]) -> Bool {
        if let isAvailable = value["isAvailable"] as? Bool {
            return isAvailable
        }
        if let availability = value["availability"] as? String {
            return !availability.localizedCaseInsensitiveContains("unavailable")
        }
        return true
    }
}
