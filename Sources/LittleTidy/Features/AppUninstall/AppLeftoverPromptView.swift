import AppKit
import LittleTidyCore
import SwiftUI

struct AppLeftoverPromptView: View {
    let event: AppUninstallEvent
    let onConfirmClean: ([RelatedAppData]) -> Void
    let onDismiss: () -> Void

    @State private var selectedURLs: Set<URL>

    init(
        event: AppUninstallEvent,
        onConfirmClean: @escaping ([RelatedAppData]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.event = event
        self.onConfirmClean = onConfirmClean
        self.onDismiss = onDismiss
        _selectedURLs = State(initialValue: Set(event.leftovers.map(\.url)))
    }

    private var selectedBytes: Int64 {
        event.leftovers
            .filter { selectedURLs.contains($0.url) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    private var selectedLeftovers: [RelatedAppData] {
        event.leftovers.filter { selectedURLs.contains($0.url) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.cleanerWarning)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.displayName) è stata disinstallata")
                        .font(.title2.weight(.bold))
                    Text("Bundle ID: \(event.bundleIdentifier)\(event.version.map { " · v\($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Sono stati individuati file residui in Library associati a questa applicazione. Puoi esaminarli e spostarli nel Cestino.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .cleanerSurface()

            HStack {
                Text("\(selectedLeftovers.count) di \(event.leftovers.count) elementi selezionati")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Spazio liberabile: \(ByteCountFormatter.cleanerString(from: selectedBytes))")
                    .font(.headline)
                    .foregroundStyle(Color.cleanerSuccess)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(event.leftovers, id: \.url) { leftover in
                        LeftoverItemRow(
                            leftover: leftover,
                            isSelected: selectedURLs.contains(leftover.url),
                            toggleSelection: {
                                if selectedURLs.contains(leftover.url) {
                                    selectedURLs.remove(leftover.url)
                                } else {
                                    selectedURLs.insert(leftover.url)
                                }
                            },
                            revealInFinder: {
                                NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
                            }
                        )
                        if leftover != event.leftovers.last {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
                .cleanerSubtleSurface()
            }
            .frame(maxHeight: 280)

            HStack {
                Button("Conserva tutto", action: onDismiss)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onConfirmClean(selectedLeftovers)
                } label: {
                    Label("Sposta \(ByteCountFormatter.cleanerString(from: selectedBytes)) nel Cestino", systemImage: "trash")
                }
                .buttonStyle(.glassProminent)
                .disabled(selectedLeftovers.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 540, maxWidth: 620)
    }
}

private struct LeftoverItemRow: View {
    let leftover: RelatedAppData
    let isSelected: Bool
    let toggleSelection: () -> Void
    let revealInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .controlSize(.regular)
            .accessibilityLabel("Seleziona \(leftover.kind)")

            Image(systemName: iconName(for: leftover.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(leftover.kind)
                        .font(.subheadline.weight(.medium))
                    Text("· \(leftover.url.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(leftover.url.path(percentEncoded: false))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(ByteCountFormatter.cleanerString(from: leftover.sizeBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: revealInFinder) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Rivela nel Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "Application Support": return "folder.badge.gearshape"
        case "Caches": return "shippingbox"
        case "Container": return "shippingbox.fill"
        case "Preferences": return "gearshape"
        case "Saved state": return "clock.arrow.circlepath"
        case "Logs": return "doc.text"
        case "Launch agent": return "bolt.fill"
        default: return "folder"
        }
    }
}
