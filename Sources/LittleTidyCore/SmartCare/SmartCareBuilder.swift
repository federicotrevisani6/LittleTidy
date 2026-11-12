import Foundation

/// What each analyzer found, before ownership is resolved.
public struct SmartCareInputs: Sendable {
    public var entries: [SmartCareCardID: [SmartCareEntry]]
    public var states: [SmartCareCardID: SmartCareCardState]
    public var infoText: [SmartCareCardID: String]

    public init(
        entries: [SmartCareCardID: [SmartCareEntry]] = [:],
        states: [SmartCareCardID: SmartCareCardState] = [:],
        infoText: [SmartCareCardID: String] = [:]
    ) {
        self.entries = entries
        self.states = states
        self.infoText = infoText
    }
}

/// Pure mapping from analyzer output to cards. It applies the count-once
/// precedence, derives each card's state and computes the headline.
public enum SmartCareBuilder {
    public static func cards(from inputs: SmartCareInputs) -> [SmartCareCard] {
        var claimed: [String] = []
        var cards: [SmartCareCard] = []

        for id in SmartCareCardID.allCases {
            let found = inputs.entries[id] ?? []
            let owned = found.filter { entry in !isClaimed(entry.path, by: claimed) }
            claimed.append(contentsOf: owned.map(\.path))

            let state = resolvedState(owned: owned, requested: inputs.states[id], hasInfo: inputs.infoText[id] != nil)
            cards.append(SmartCareCard(
                cardID: id,
                state: state,
                entries: owned,
                infoText: inputs.infoText[id]
            ))
        }
        return cards
    }

    public static func headline(for cards: [SmartCareCard]) -> SmartCareHeadline {
        // The Trash is never part of the "safe" total: emptying it is permanent.
        let safe = cards
            .filter { $0.cardID != .trash }
            .reduce(Int64(0)) { $0 + $1.recommendedBytes }
        let review = cards.reduce(Int64(0)) { $0 + $1.reviewBytes }
        return SmartCareHeadline(safeBytes: safe, reviewBytes: review)
    }

    /// An entry is claimed when a higher card already owns the same path, a
    /// folder containing it, or something inside it.
    static func isClaimed(_ path: String, by claimed: [String]) -> Bool {
        let normalized = normalize(path)
        return claimed.contains { other in
            let owner = normalize(other)
            return owner == normalized
                || normalized.hasPrefix(owner + "/")
                || owner.hasPrefix(normalized + "/")
        }
    }

    private static func normalize(_ path: String) -> String {
        var result = URL(fileURLWithPath: path).standardizedFileURL.path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    private static func resolvedState(
        owned: [SmartCareEntry],
        requested: SmartCareCardState?,
        hasInfo: Bool
    ) -> SmartCareCardState {
        switch requested {
        case .scanning, .needsAccess, .needsFolder, .failed, .blocked:
            // Unknown is never zero: these states keep their message.
            return requested ?? .ready
        case .ready, .empty, nil:
            return owned.isEmpty && !hasInfo ? .empty : .ready
        }
    }
}
