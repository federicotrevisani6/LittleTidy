import AppKit
import LittleTidyCore
import SwiftUI

/// Explains what each macOS permission unlocks and takes the person to the
/// right Settings pane with one click. Nothing here is required: without a
/// permission the affected cards say "Needs access" and the rest works.
struct PermissionGuideSheet: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SmartCareTile(symbol: "lock.open", tint: Color.accentColor, fill: Color.accentColor.opacity(0.14), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What LittleTidy can read").font(.title2.weight(.semibold))
                    Text("None of this is required. Without a permission, only the cards that need it say \"Needs access\".")
                        .font(.callout)
                        .foregroundStyle(Color.cleanerSecondaryText)
                }
            }

            ForEach(store.permissionItems) { item in
                SmartCarePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.kind.title).font(.headline)
                            Spacer()
                            stateChip(item.state)
                        }
                        Text(item.kind.unlocks)
                            .font(.callout)
                            .foregroundStyle(Color.cleanerSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.kind.affectedCards.isEmpty {
                            Text("Cards: " + item.kind.affectedCards.map(\.title).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(Color.cleanerSecondaryText)
                        }
                        if item.state == .notConfirmed {
                            Button("Open System Settings…") { store.openFullDiskAccessSettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            Label("LittleTidy reads these locations on this Mac only. Nothing is sent anywhere.", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)

            HStack {
                Spacer()
                if store.permissionItems.contains(where: { $0.state == .notConfirmed }) {
                    Button("Not Now") { store.dismissPermissionGuide() }.keyboardShortcut(.cancelAction)
                    Button("Done") { store.dismissPermissionGuide() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { store.dismissPermissionGuide() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.recheckPermissions()
        }
    }

    @ViewBuilder
    private func stateChip(_ state: PermissionState) -> some View {
        switch state {
        case .confirmed:
            SmartCareChip(text: state.label, tint: Color.cleanerSuccessText, fill: Color.cleanerSuccess)
        case .notConfirmed:
            SmartCareChip(text: state.label, tint: Color.cleanerWarningText, fill: Color.cleanerWarning)
        }
    }
}
