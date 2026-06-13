import SwiftUI

extension View {
    func cleanerSurface(cornerRadius: CGFloat = 8) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func cleanerSubtleSurface(cornerRadius: CGFloat = 8) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
