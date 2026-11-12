import LittleTidyCore
import SwiftUI

extension SmartCareCardID {
    var symbolName: String {
        switch self {
        case .developer: "hammer"
        case .aiTools: "brain"
        case .mailAttachments: "envelope"
        case .iosBackups: "iphone"
        case .installers: "arrow.down.circle"
        case .caches: "shippingbox"
        case .trash: "trash"
        case .unusedApps: "square.grid.2x2"
        case .snapshots: "clock.arrow.circlepath"
        case .startupItems: "power"
        }
    }
}

/// "26,4 GB" with the unit smaller and secondary, as one accessible phrase.
struct SmartCareNumber: View {
    let bytes: Int64
    @ScaledMetric private var size: CGFloat

    init(bytes: Int64, size: CGFloat) {
        self.bytes = bytes
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    var body: some View {
        let text = ByteCountFormatter.cleanerString(from: bytes)
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.first ?? text)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
            if parts.count > 1 {
                Text(parts[1])
                    .font(.system(size: size * 0.58, weight: .medium))
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A 30 pt rounded tile with an SF Symbol, tinted by role.
struct SmartCareTile: View {
    let symbol: String
    var tint: Color = Color.cleanerSecondaryText
    var fill: Color = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A short state label such as "Needs access". Words, not only colour.
struct SmartCareChip: View {
    let text: String
    let tint: Color
    let fill: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(fill.opacity(0.18), in: Capsule())
    }
}

/// A bordered block used in the sheets and the result: neutral, or edged in
/// a role colour when it carries a permanent or attention meaning.
struct SmartCarePanel<Content: View>: View {
    var edge: Color?
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? Color(nsColor: .quaternaryLabelColor)).opacity(tint == nil ? 0.08 : 0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(edge ?? Color(nsColor: .separatorColor).opacity(0.6), lineWidth: edge == nil ? 0.5 : 1)
            )
    }
}

/// Safe, review and protected parts of a card as glyph plus words.
struct SmartCareTierLine: View {
    let card: SmartCareCard

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.callout)
        .foregroundStyle(Color.cleanerSecondaryText)
    }

    @ViewBuilder
    private var items: some View {
        if card.recommendedBytes > 0 {
            item("checkmark.circle.fill", Color.cleanerSuccess, "\(ByteCountFormatter.cleanerString(from: card.recommendedBytes)) safe")
        }
        if card.reviewBytes > 0 {
            item("eye", Color.cleanerInfo, "\(ByteCountFormatter.cleanerString(from: card.reviewBytes)) to review")
        }
        if card.protectedBytes > 0 {
            item("lock", Color(nsColor: .systemGray), "\(ByteCountFormatter.cleanerString(from: card.protectedBytes)) protected")
        }
    }

    private func item(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint).imageScale(.small)
            Text(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The card's share of the largest card, split by tier. Decorative: the tier
/// line carries the meaning, so it is hidden from VoiceOver.
struct SmartCareTierBar: View {
    let card: SmartCareCard
    let largestTotal: Int64

    var body: some View {
        GeometryReader { proxy in
            let total = max(card.recommendedBytes + card.reviewBytes + card.protectedBytes, 1)
            let share = min(1, Double(total) / Double(max(largestTotal, 1)))
            let width = proxy.size.width * share
            HStack(spacing: 2) {
                segment(Color.cleanerSuccess, card.recommendedBytes, total, width)
                segment(Color.cleanerInfo, card.reviewBytes, total, width)
                segment(Color(nsColor: .systemGray), card.protectedBytes, total, width)
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12), in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ color: Color, _ bytes: Int64, _ total: Int64, _ width: CGFloat) -> some View {
        if bytes > 0 {
            Rectangle().fill(color).frame(width: max(2, width * Double(bytes) / Double(total)))
        }
    }
}
