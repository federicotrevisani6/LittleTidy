import LittleTidyCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var showingOptionsPopover = false
    @State private var showingSmartCleanConfirmation = false

    private var totalReclaimableBytes: Int64 {
        store.reclaimableBytes(for: .cache) +
        store.reclaimableBytes(for: .duplicate) +
        store.recommendedDeveloperBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // MARK: - Hero Smart Clean Header
            HeroSmartCleanCard(
                store: store,
                totalReclaimableBytes: totalReclaimableBytes,
                onStartScan: { store.startOrCancelScan() },
                onSmartClean: {
                    store.selectSuggested()
                    store.selectedSection = .cleanupPlan
                },
                onOptionsTap: { showingOptionsPopover.toggle() }
            )
            .popover(isPresented: $showingOptionsPopover, arrowEdge: .top) {
                ScanOptionsPopoverView(store: store)
                    .frame(width: 360)
                    .padding()
            }

            // MARK: - Readiness Alerts
            if !store.permissionReadinessItems.isEmpty {
                PermissionBanner(items: store.permissionReadinessItems)
            }

            // MARK: - Categorized Recommendation Cards
            Text("Categorie di Pulizia")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                CategorySmartCard(
                    title: "Cache di Sistema & App",
                    subtitle: "File temporanei e log rigenerabili in sicurezza",
                    icon: "shippingbox.fill",
                    color: .green,
                    sizeBytes: store.reclaimableBytes(for: .cache),
                    badge: "Sicuro",
                    badgeColor: .green,
                    actionTitle: "Esamina Cache",
                    onAction: { store.selectedSection = .caches }
                )

                CategorySmartCard(
                    title: "Sviluppo & Xcode",
                    subtitle: "DerivedData, cache SPM e simulatori orfani",
                    icon: "hammer.fill",
                    color: .blue,
                    sizeBytes: store.recommendedDeveloperBytes,
                    badge: "Consigliato",
                    badgeColor: .blue,
                    actionTitle: "Esamina Xcode",
                    onAction: { store.selectedSection = .developerStorage }
                )

                CategorySmartCard(
                    title: "File Duplicati",
                    subtitle: "Copie byte-per-byte identiche",
                    icon: "doc.on.doc.fill",
                    color: .orange,
                    sizeBytes: store.reclaimableBytes(for: .duplicate),
                    badge: "Revisione",
                    badgeColor: .orange,
                    actionTitle: "Vedi Duplicati",
                    onAction: { store.selectedSection = .duplicates }
                )

                CategorySmartCard(
                    title: "Grandi File",
                    subtitle: "Installer, video e archivi pesanti non usati di recente",
                    icon: "internaldrive.fill",
                    color: .purple,
                    sizeBytes: store.reclaimableBytes(for: .largeFile),
                    badge: "Manuale",
                    badgeColor: .secondary,
                    actionTitle: "Esamina File",
                    onAction: { store.selectedSection = .largeFiles }
                )

                CategorySmartCard(
                    title: "App & Residui",
                    subtitle: "Applicazioni e dati residui in ~/Library",
                    icon: "app.badge.checkmark",
                    color: .pink,
                    sizeBytes: store.reclaimableBytes(for: .unusedApp),
                    badge: "Manuale",
                    badgeColor: .secondary,
                    actionTitle: "Gestisci App",
                    onAction: { store.selectedSection = .unusedApps }
                )
            }

            // MARK: - Storage Breakdown Preview
            if !store.folderUsage.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Cartelle Più Pesanti")
                            .font(.headline)
                        Spacer()
                        Button {
                            store.selectedSection = .storage
                        } label: {
                            Label("Apri Mappa Completa", systemImage: "chart.pie.fill")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 8) {
                        ForEach(store.folderUsage.prefix(4), id: \.url) { folder in
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(folder.url.lastPathComponent)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(folder.url.deletingLastPathComponent().path(percentEncoded: false))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(ByteCountFormatter.cleanerString(from: folder.bytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .cleanerSubtleSurface()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Hero Smart Clean Card

private struct HeroSmartCleanCard: View {
    @ObservedObject var store: ScanReviewStore
    let totalReclaimableBytes: Int64
    let onStartScan: () -> Void
    let onSmartClean: () -> Void
    let onOptionsTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text(heroTitle)
                            .font(.title2.weight(.bold))
                    }

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onOptionsTap) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Opzioni di scansione avanzate")
            }

            // Reclaimable metric badge if scanned
            if totalReclaimableBytes > 0 && !store.isScanning {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spazio liberabile consigliato")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ByteCountFormatter.cleanerString(from: totalReclaimableBytes))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.cleanerSuccess)
                    }

                    Spacer()

                    Button {
                        onSmartClean()
                    } label: {
                        Label("⚡ Pulisci \(ByteCountFormatter.cleanerString(from: totalReclaimableBytes))", systemImage: "trash.fill")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(14)
                .background(Color.cleanerSuccess.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Main Scan Action Bar
            HStack(spacing: 12) {
                Button {
                    onStartScan()
                } label: {
                    HStack(spacing: 8) {
                        if store.isScanning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Annulla Scansione")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Scansiona Ora")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    store.chooseFolders()
                } label: {
                    Label("Cartelle Personalizzate", systemImage: "folder.badge.plus")
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .disabled(store.isScanning)
            }
        }
        .padding(20)
        .cleanerSurface()
    }

    private var heroTitle: String {
        if store.isScanning {
            return "Scansione in corso..."
        }
        if totalReclaimableBytes > 0 {
            return "Pronto per la pulizia"
        }
        return "Smart Clean"
    }

    private var heroSubtitle: String {
        if store.isScanning {
            return store.statusMessage
        }
        if totalReclaimableBytes > 0 {
            return "Trovati file temporanei, cache e duplicati pronti per essere rimossi in sicurezza."
        }
        return "Analizza rapidamente il tuo Mac per individuare file obsoleti, cache e duplicati."
    }
}

// MARK: - Category Smart Card

private struct CategorySmartCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let sizeBytes: Int64
    let badge: String
    let badgeColor: Color
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()

                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            HStack {
                Text(ByteCountFormatter.cleanerString(from: sizeBytes))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(sizeBytes > 0 ? Color.primary : Color.secondary)

                Spacer()

                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .cleanerSubtleSurface()
    }
}

// MARK: - Options Popover

private struct ScanOptionsPopoverView: View {
    @ObservedObject var store: ScanReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Opzioni Avanzate di Scansione", systemImage: "slider.horizontal.3")
                .font(.headline)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Minimo duplicati")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(ByteCountFormatter.cleanerString(from: store.minimumDuplicateSize), value: $store.minimumDuplicateSize, in: 0...100_000_000, step: 500_000)
                        .controlSize(.small)
                }

                GridRow {
                    Text("Soglia file grandi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(ByteCountFormatter.cleanerString(from: store.largeFileThreshold), value: $store.largeFileThreshold, in: 1_000_000...20_000_000_000, step: 100_000_000)
                        .controlSize(.small)
                }

                GridRow {
                    Text("File nascosti")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Includi", isOn: $store.includeHiddenFiles)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }

                GridRow {
                    Text("Cartelle di sistema")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Consenti", isOn: $store.includeSystemFolders)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }

                GridRow {
                    Text("Monitoraggio Cestino")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Attivo", isOn: $store.enableTrashWatcher)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }

            Divider()

            HStack {
                Button("Ripristina Predefiniti") {
                    store.resetScanSettings()
                }
                .controlSize(.small)

                Spacer()
            }
        }
    }
}

// MARK: - Permission Banner

private struct PermissionBanner: View {
    let items: [PermissionReadinessItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accesso alle cartelle richiesto", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cleanerWarning)

            ForEach(items, id: \.id) { item in
                Text("• \(item.title): \(item.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}
