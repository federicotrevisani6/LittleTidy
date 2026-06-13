import Foundation

struct CleanupPlanValidation {
    enum State {
        case noSelection
        case ready
        case blocked
    }

    let state: State
    let title: String
    let detail: String
    let warnings: [String]

    var canMoveToTrash: Bool {
        state == .ready
    }
}
