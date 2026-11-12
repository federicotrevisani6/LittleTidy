import LittleTidyCore
import SwiftUI

/// The launchd items that start with the Mac, explained. Only this user's own
/// items can be switched, and switching never deletes a file.
struct StartupItemsSheet: View {
    @ObservedObject var store: ScanReviewStore

    private var broken: [StartupItem] { store.startupItems.filter(\.isBroken) }
    private var apps: [StartupItem] { store.startupItems.filter { !$0.isBroken && !$0.isApple } }
    private var apple: [StartupItem] { store.startupItems.filter { !$0.isBroken && $0.isApple } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SmartCareTile(symbol: "power", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Login and background items").font(.title2.weight(.semibold))
                    Text("Covers launchd items only. Items an app registers in System Settings, Login Items & Extensions are not listed here.")
                        .font(.callout)
                        .foregroundStyle(Color.cleanerSecondaryText)
                }
            }

            if let message = store.startupMessage {
                SmartCarePanel(tint: Color.cleanerInfo) {
                    Label(message, systemImage: "info.circle").font(.callout)
                }
            }

            if !store.startupAccessIssues.isEmpty {
                SmartCarePanel(edge: Color.cleanerWarning, tint: Color.cleanerWarning) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Some folders could not be read", systemImage: "lock")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.cleanerWarningText)
                        ForEach(store.startupAccessIssues, id: \.self) { issue in
                            Text(issue).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText)
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.startupItems.isEmpty {
                        Label(store.isScanningStartupItems ? "Reading…" : "No launchd items found.", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.cleanerSecondaryText)
                    }
                    if !broken.isEmpty {
                        section("Point to something that is gone", broken, note: "The program these start no longer exists. Usually the app was removed.")
                    }
                    if !apps.isEmpty { section("Apps and tools", apps, note: nil) }
                    if !apple.isEmpty {
                        DisclosureGroup("Apple and system (\(apple.count))") {
                            VStack(spacing: 8) { ForEach(apple) { row($0) } }.padding(.top, 8)
                        }
                        .font(.headline)
                    }
                }
            }
            .frame(maxHeight: 420)

            Text("Switching an item off only stops it from starting at login. LittleTidy never deletes the file or the program, and switching it back on undoes it.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)

            HStack {
                Spacer()
                Button("Done") { store.showStartupItems = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 660)
    }

    private func section(_ title: String, _ items: [StartupItem], note: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(items.count))").font(.headline)
            if let note { Text(note).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText) }
            ForEach(items) { row($0) }
        }
    }

    private func row(_ item: StartupItem) -> some View {
        SmartCarePanel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                        SmartCareChip(text: item.scope.label, tint: Color.cleanerSecondaryText, fill: Color(nsColor: .systemGray))
                        if item.isBroken { SmartCareChip(text: "Broken", tint: Color.cleanerDangerText, fill: Color.cleanerDanger) }
                        if item.isDisabled == true { SmartCareChip(text: "Off", tint: Color.cleanerSecondaryText, fill: Color(nsColor: .systemGray)) }
                        if item.isLoaded == true { SmartCareChip(text: "Running", tint: Color.cleanerSuccessText, fill: Color.cleanerSuccess) }
                    }
                    Text(item.label).font(.subheadline).foregroundStyle(Color.cleanerSecondaryText).lineLimit(1).truncationMode(.middle)
                    if let executable = item.executable {
                        Text(executable).font(.caption).foregroundStyle(Color.cleanerSecondaryText).lineLimit(1).truncationMode(.middle)
                    }
                    if item.isBroken {
                        Text("The program it starts is not there any more.").font(.subheadline).foregroundStyle(Color.cleanerDangerText)
                    }
                }
                Spacer(minLength: 8)
                control(item)
            }
        }
    }

    @ViewBuilder
    private func control(_ item: StartupItem) -> some View {
        if item.canChange {
            Toggle("Starts at login", isOn: Binding(
                get: { item.isDisabled != true },
                set: { store.setStartsAtLogin($0, item: item) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(store.changingStartupItemID != nil)
            .accessibilityLabel("Starts at login: \(item.displayName)")
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "lock").foregroundStyle(Color.cleanerSecondaryText)
                Text(item.isApple ? "Apple's" : "Not changed by LittleTidy")
                    .font(.caption)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
        }
    }
}
