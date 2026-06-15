import SwiftUI

extension View {
    func cleanerSurface(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func cleanerSubtleSurface(cornerRadius: CGFloat = 14) -> some View {
        glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func cleanerInteractiveSurface(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
