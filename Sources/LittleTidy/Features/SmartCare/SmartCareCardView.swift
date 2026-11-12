import LittleTidyCore
import SwiftUI

/// Every Smart Care category is one of these: the same box, in the same
/// places, whether it has something to clean or not. Header, one value, one
/// short line, a few small notices, one sentence of explanation, and buttons.
struct SmartCareCardView: View {
    let card: SmartCareCard
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
    var chooseFolder: () -> Void = {}
    var openTrash: () -> Void = {}
    var emptyTrash: () -> Void = {}

    private var title: String { card.cardID.title }
    private var totalBytes: Int64 { card.recommendedBytes + card.reviewBytes + card.protectedBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                SmartCareTile(symbol: card.cardID.symbolName)
                Text(title).font(.headline)
                Spacer(minLength: 4)
                chip
            }
            valueArea
                .frame(minHeight: 58, alignment: .topLeading)
            notices
            Text(card.cardID.explanation)
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            buttons
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .cleanerInteractiveSurface(cornerRadius: 12)
        .opacity(card.isEmpty ? 0.78 : 1)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chip

    @ViewBuilder
    private var chip: some View {
        switch card.state {
        case .needsAccess:
            SmartCareChip(text: "Needs access", tint: Color.cleanerWarningText, fill: Color.cleanerWarning)
        case .needsFolder:
            SmartCareChip(text: "Needs a folder", tint: Color.cleanerWarningText, fill: Color.cleanerWarning)
        case .failed:
            SmartCareChip(text: "Failed", tint: Color.cleanerDangerText, fill: Color.cleanerDanger)
        default:
            EmptyView()
        }
    }

    // MARK: - The one value

    @ViewBuilder
    private var valueArea: some View {
        switch card.state {
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…").foregroundStyle(Color.cleanerSecondaryText)
            }
        case .needsAccess(let message), .needsFolder(let message):
            Label(message, systemImage: card.state.isFolderState ? "folder.badge.plus" : "lock")
                .font(.callout)
        case .blocked(let message):
            Label(message, systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(Color.cleanerWarningText)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.cleanerDangerText)
        case .empty:
            Label("Nothing to clean", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(Color.cleanerSecondaryText)
        case .ready:
            readyValue
        }
    }

    @ViewBuilder
    private var readyValue: some View {
        if let headline = card.headlineText {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                if let info = card.infoText {
                    Text(info).font(.callout).foregroundStyle(Color.cleanerSecondaryText).lineLimit(2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, headline, card.infoText].compactMap { $0 }.joined(separator: ", "))
        } else if card.cardID == .trash {
            VStack(alignment: .leading, spacing: 4) {
                SmartCareNumber(bytes: totalBytes, size: 26)
                Text("\(card.itemCount) items · not in either total")
                    .font(.callout)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(ByteCountFormatter.cleanerString(from: totalBytes)), \(card.itemCount) items")
        } else if let value = actionable {
            VStack(alignment: .leading, spacing: 4) {
                SmartCareNumber(bytes: value.bytes, size: 26)
                Text(value.caption)
                    .font(.callout)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(value.bytes == 0 ? "" : ByteCountFormatter.cleanerString(from: value.bytes)), \(value.caption)")
        }
    }

    /// The one amount a person can act on: the safe part if there is one,
    /// otherwise what is left to review. The rest is in the review sheet.
    private var actionable: (bytes: Int64, caption: String)? {
        if card.recommendedBytes > 0 {
            let more = card.reviewBytes > 0 ? " · +\(ByteCountFormatter.cleanerString(from: card.reviewBytes)) to review" : ""
            return (card.recommendedBytes, "safe to clean" + more)
        }
        if card.reviewBytes > 0 {
            return (card.reviewBytes, card.itemCount > 1 ? "to review · \(card.itemCount) items" : "to review")
        }
        if card.protectedBytes > 0 {
            return (card.protectedBytes, "protected, not removed")
        }
        let unrecognised = card.bytes(for: .unclassified)
        if unrecognised > 0 {
            return (unrecognised, "not recognised, never removed")
        }
        return nil
    }

    // MARK: - Notices

    /// Words and a glyph, never colour alone, and never more than two.
    @ViewBuilder
    private var notices: some View {
        if permanentBytes > 0 || leftOutCount > 0 {
            HStack(spacing: 6) {
                if permanentBytes > 0 {
                    notice("exclamationmark.triangle.fill", "\(ByteCountFormatter.cleanerString(from: permanentBytes)) removed for good", Color.cleanerDangerText, Color.cleanerDanger)
                }
                if leftOutCount > 0 {
                    notice("hand.raised", leftOutCount == 1 ? "1 item left out" : "\(leftOutCount) items left out", Color.cleanerWarningText, Color.cleanerWarning)
                        .help("\(ByteCountFormatter.cleanerString(from: leftOutBytes)) left out for now: quit Xcode to include.")
                }
            }
        }
    }

    private func notice(_ symbol: String, _ text: String, _ tint: Color, _ fill: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(fill.opacity(0.16), in: Capsule())
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            if card.cardID == .trash, case .ready = card.state {
                Button("Open Trash", action: openTrash)
                Button(role: .destructive, action: emptyTrash) {
                    Label("Empty Trash…", systemImage: "trash").foregroundStyle(Color.cleanerDangerText)
                }
                .disabled(isBusy || card.itemCount == 0)
            } else {
                switch card.state {
                case .needsAccess:
                    Button("Allow Access…", action: allowAccess)
                case .needsFolder:
                    Button("Choose Folder…", action: chooseFolder)
                case .scanning, .failed, .blocked, .empty:
                    EmptyView()
                case .ready:
                    Button("Review", action: review)
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
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 24)
    }
}

private extension SmartCareCardState {
    var isFolderState: Bool {
        if case .needsFolder = self { return true }
        return false
    }
}
