import LittleTidyCore
import SwiftUI

/// One Smart Care card: header, one number, tier split and bar, one sentence
/// of explanation and at most two buttons. See the design handoff, section 4.
struct SmartCareCardView: View {
    let card: SmartCareCard
    let largestTotal: Int64
    /// Items on this card a safety rule leaves out right now (for example
    /// while Xcode runs), and their size.
    var leftOutCount = 0
    var leftOutBytes: Int64 = 0
    /// Bytes of this card's safe items that are removed for good.
    var permanentBytes: Int64 = 0
    let isBusy: Bool
    let review: () -> Void
    let clean: () -> Void
    let allowAccess: () -> Void

    private var totalBytes: Int64 { card.recommendedBytes + card.reviewBytes + card.protectedBytes }
    private var title: String { card.cardID.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                SmartCareTile(symbol: card.cardID.symbolName)
                Text(title).font(.headline)
                Spacer(minLength: 4)
                chip
            }
            content
            Text(card.cardID.explanation)
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            buttons
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .cleanerInteractiveSurface(cornerRadius: 12)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chip

    @ViewBuilder
    private var chip: some View {
        switch card.state {
        case .needsAccess:
            SmartCareChip(text: "Needs access", tint: Color.cleanerWarningText, fill: Color.cleanerWarning)
        case .failed:
            SmartCareChip(text: "Failed", tint: Color.cleanerDangerText, fill: Color.cleanerDanger)
        default:
            EmptyView()
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch card.state {
        case .scanning:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(Color.cleanerSecondaryText)
                }
                skeleton(width: 120)
                skeleton(width: 200)
            }
        case .needsAccess(let message):
            Label(message, systemImage: "lock")
                .font(.callout)
        case .blocked(let message):
            Label(message, systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(Color.cleanerWarningText)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.cleanerDangerText)
        case .empty, .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if totalBytes > 0 {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    if card.recommendedBytes == 0, card.protectedBytes == 0 {
                        SmartCareNumber(bytes: totalBytes, size: 26)
                        Text(allReviewText)
                            .font(.callout)
                            .foregroundStyle(Color.cleanerSecondaryText)
                    } else {
                        SmartCareNumber(bytes: totalBytes, size: 26)
                        SmartCareTierLine(card: card)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summaryLabel)
                SmartCareTierBar(card: card, largestTotal: largestTotal)
            }
            if permanentBytes > 0 {
                Label("\(ByteCountFormatter.cleanerString(from: permanentBytes)) of this is removed for good.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.cleanerDangerText)
            }
            if leftOutCount > 0 {
                Label("\(leftOutCount == 1 ? "1 item" : "\(leftOutCount) items") (\(ByteCountFormatter.cleanerString(from: leftOutBytes))) left out for now: quit Xcode to include.",
                      systemImage: "hand.raised")
                    .font(.callout)
                    .foregroundStyle(Color.cleanerWarningText)
            }
        } else if let info = card.infoText {
            Text(info).font(.callout).foregroundStyle(Color.cleanerSecondaryText)
        }
    }

    private var allReviewText: String {
        card.itemCount > 1 ? "\(card.itemCount) items, all to review" : "All of it to review"
    }

    private var summaryLabel: String {
        var parts = [title, ByteCountFormatter.cleanerString(from: totalBytes)]
        if card.recommendedBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.recommendedBytes)) safe") }
        if card.reviewBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.reviewBytes)) to review") }
        if card.protectedBytes > 0 { parts.append("\(ByteCountFormatter.cleanerString(from: card.protectedBytes)) protected") }
        return parts.joined(separator: ", ")
    }

    private func skeleton(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.16))
            .frame(width: width, height: 10)
            .accessibilityHidden(true)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            switch card.state {
            case .needsAccess:
                Button("Allow Access…", action: allowAccess)
            case .scanning, .failed, .blocked:
                EmptyView()
            case .empty, .ready:
                if card.reviewBytes > 0 || card.recommendedBytes > 0 || card.itemCount > 0 || card.infoText != nil {
                    Button("Review", action: review)
                }
                if card.canClean {
                    Button(action: clean) {
                        HStack(spacing: 4) {
                            if permanentBytes > 0 {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.cleanerDangerText)
                            }
                            Text("Clean \(ByteCountFormatter.cleanerString(from: card.recommendedBytes))…")
                                .foregroundStyle(isBusy ? Color.secondary : Color.accentColor)
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("Clean \(title), \(ByteCountFormatter.cleanerString(from: card.recommendedBytes))")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// The Trash: the only place with a permanent action, so it is a full-width
/// row with its own red button, never a fourth card.
struct SmartCareTrashRow: View {
    let card: SmartCareCard
    let isBusy: Bool
    let open: () -> Void
    let empty: () -> Void
    let allowAccess: () -> Void

    private var totalBytes: Int64 { card.recommendedBytes + card.reviewBytes }

    var body: some View {
        HStack(spacing: 14) {
            SmartCareTile(symbol: "trash", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.cardID.title).font(.headline)
                Text(card.cardID.explanation)
                    .font(.subheadline)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
            Spacer(minLength: 12)
            switch card.state {
            case .needsAccess(let message):
                SmartCareChip(text: "Needs access", tint: Color.cleanerWarningText, fill: Color.cleanerWarning)
                Text(message).font(.callout)
                Button("Allow Access…", action: allowAccess).buttonStyle(.bordered).controlSize(.small)
            default:
                VStack(alignment: .trailing, spacing: 2) {
                    SmartCareNumber(bytes: totalBytes, size: 22)
                    Text(isBusy ? "Updating after the cleanup…" : "\(card.itemCount) items · not in either total")
                        .font(.subheadline)
                        .foregroundStyle(Color.cleanerSecondaryText)
                }
                HStack {
                    Button("Open Trash", action: open)
                    Button(role: .destructive, action: empty) {
                        Label("Empty Trash…", systemImage: "trash")
                            .foregroundStyle(Color.cleanerDangerText)
                    }
                    .disabled(isBusy || card.itemCount == 0)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cleanerInteractiveSurface(cornerRadius: 12)
        .accessibilityElement(children: .contain)
    }
}
