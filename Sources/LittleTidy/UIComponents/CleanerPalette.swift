import AppKit
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

    // MARK: Text tokens
    //
    // System green, orange, blue and red fail 4.5:1 as small text on a card,
    // so text uses these darker (light) and lighter (dark) variants. Glyphs,
    // bars and tinted fills keep the system colors above.

    /// Text for the safe tier and success.
    static let cleanerSuccessText = dynamic(light: 0x1B7F3B, dark: 0x4BDE76)
    /// Text for the review tier and information.
    static let cleanerInfoText = dynamic(light: 0x0A5FC4, dark: 0x6CB0FF)
    /// Text for attention: needs access, blocked, skipped, snapshot.
    static let cleanerWarningText = dynamic(light: 0x8F4A00, dark: 0xFFB84D)
    /// Text for failed, permanent and destructive outcomes.
    static let cleanerDangerText = dynamic(light: 0xC0261B, dark: 0xFF8A80)
    /// Secondary text at 11 to 12 pt. `.secondary` is about 4:1 on a white
    /// card in light mode, so this is the label color at 80% (66% in dark).
    static let cleanerSecondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.labelColor.withAlphaComponent(isDark ? 0.66 : 0.8)
    })

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
