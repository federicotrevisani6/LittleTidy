import AppKit
import SwiftUI

extension View {
    func cleanerSurface(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }

    func cleanerSubtleSurface(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func cleanerInteractiveSurface(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
            )
    }
}
