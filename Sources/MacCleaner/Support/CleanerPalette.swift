import SwiftUI

/// Semantic colors used across the app. Defined once so meaning (success,
/// warning, …) is consistent, and backed by AppKit system colors so they adapt
/// to Dark Mode, accentuated contrast, and the user's accessibility settings.
extension Color {
    /// Positive / completed / safe-to-remove.
    static let cleanerSuccess = Color(nsColor: .systemGreen)
    /// Caution that needs attention but is not blocking.
    static let cleanerWarning = Color(nsColor: .systemOrange)
    /// Neutral, informational guidance.
    static let cleanerInfo = Color(nsColor: .systemBlue)
    /// Blocking error / destructive outcome.
    static let cleanerDanger = Color(nsColor: .systemRed)
}
