import AppKit
import LittleTidyCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ScanReviewStore

    private var totalReclaimableBytes: Int64 {
        store.reclaimableBytes(for: .cache) +
        store.reclaimableBytes(for: .duplicate) +
        store.recommendedDeveloperBytes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Header & Status
                overviewHeader

                // MARK: - Storage Capacity Breakdown Bar
                storageBreakdownBar

                // MARK: - Permission Warnings (if any)
                if !store.permissionReadinessItems.isEmpty && store.hasPermissionWarnings {
                    PermissionBanner(items: store.permissionReadinessItems)
                }

                // MARK: - Category Breakdown Table
                categoryBreakdownSection

                // MARK: - Largest Folders Preview
                if !store.folderUsage.isEmpty {
                    largestFoldersSection
                }
            }
            .padding(24)
        }
    }

    // MARK: - Header

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("System Storage Overview")
                    .font(.title2.weight(.semibold))

                if store.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if totalReclaimableBytes > 0 {
                    Text("\(ByteCountFormatter.cleanerString(from: totalReclaimableBytes)) recommended for cleanup across \(store.items.count) analyzed items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Scanned locations up to date. No pending cleanup items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if totalReclaimableBytes > 0 && !store.isScanning {
                Button {
                    store.selectSuggested()
                    store.selectedSection = .cleanupPlan
                } label: {
                    Label(
                        "Review & Clean (\(ByteCountFormatter.cleanerString(from: totalReclaimableBytes)))",
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                store.startOrCancelScan()
            } label: {
                Label(
                    store.isScanning ? "Cancel Scan" : "Scan Now",
                    systemImage: store.isScanning ? "xmark.circle" : "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Segmented Storage Bar

    private var storageBreakdownBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Storage Breakdown")
                    .font(.headline)
                Spacer()
                Text("\(ByteCountFormatter.cleanerString(from: store.scannedBytes + store.totalDeveloperBytes)) analyzed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Segmented Bar
            GeometryReader { geometry in
                let total = max(1, Double(store.scannedBytes + store.totalDeveloperBytes))
                let devWidth = CGFloat(Double(store.totalDeveloperBytes) / total) * geometry.size.width
                let cacheWidth = CGFloat(Double(store.reclaimableBytes(for: .cache)) / total) * geometry.size.width
                let dupWidth = CGFloat(Double(store.reclaimableBytes(for: .duplicate)) / total) * geometry.size.width
                let largeWidth = CGFloat(Double(store.reclaimableBytes(for: .largeFile)) / total) * geometry.size.width
                let appWidth = CGFloat(Double(store.reclaimableBytes(for: .unusedApp)) / total) * geometry.size.width

                HStack(spacing: 2) {
                    if devWidth > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: max(3, devWidth))
                    }
                    if cacheWidth > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: max(3, cacheWidth))
                    }
                    if dupWidth > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: max(3, dupWidth))
                    }
                    if largeWidth > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: max(3, largeWidth))
                    }
                    if appWidth > 0 {
                        Rectangle()
                            .fill(Color.pink)
                            .frame(width: max(3, appWidth))
                    }
                    Rectangle()
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 14)

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .blue, title: "Developer", size: store.totalDeveloperBytes)
                LegendItem(color: .green, title: "Caches", size: store.reclaimableBytes(for: .cache))
                LegendItem(color: .orange, title: "Duplicates", size: store.reclaimableBytes(for: .duplicate))
                LegendItem(color: .purple, title: "Large Files", size: store.reclaimableBytes(for: .largeFile))
                LegendItem(color: .pink, title: "Apps", size: store.reclaimableBytes(for: .unusedApp))
            }
        }
        .padding(16)
        .cleanerSurface()
    }

    // MARK: - Category Breakdown Table

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.headline)

            VStack(spacing: 0) {
                CategoryRow(
                    title: "Developer Storage",
                    detail: "Xcode DerivedData, simulators, package caches, local AI models",
                    systemImage: "hammer",
                    color: .blue,
                    totalBytes: store.totalDeveloperBytes,
                    reclaimableBytes: store.recommendedDeveloperBytes,
                    action: { store.selectedSection = .developerStorage }
                )

                Divider()

                CategoryRow(
                    title: "Application Caches",
                    detail: "User application caches in ~/Library/Caches and dev toolcaches",
                    systemImage: "shippingbox",
                    color: .green,
                    totalBytes: store.reclaimableBytes(for: .cache),
                    reclaimableBytes: store.reclaimableBytes(for: .cache),
                    action: { store.selectedSection = .caches }
                )

                Divider()

                CategoryRow(
                    title: "Duplicate Files",
                    detail: "Exact byte-for-byte duplicate copies verified by SHA-256 hash",
                    systemImage: "doc.on.doc",
                    color: .orange,
                    totalBytes: store.reclaimableBytes(for: .duplicate),
                    reclaimableBytes: store.reclaimableBytes(for: .duplicate),
                    action: { store.selectedSection = .duplicates }
                )

                Divider()

                CategoryRow(
                    title: "Large Files",
                    detail: "Files, disk images, and archives exceeding the threshold",
                    systemImage: "internaldrive",
                    color: .purple,
                    totalBytes: store.reclaimableBytes(for: .largeFile),
                    reclaimableBytes: store.reclaimableBytes(for: .largeFile),
                    action: { store.selectedSection = .largeFiles }
                )

                Divider()

                CategoryRow(
                    title: "Applications",
                    detail: "Installed applications and associated ~/Library support data",
                    systemImage: "app.badge",
                    color: .pink,
                    totalBytes: store.reclaimableBytes(for: .unusedApp),
                    reclaimableBytes: store.reclaimableBytes(for: .unusedApp),
                    action: { store.selectedSection = .unusedApps }
                )

                Divider()

                CategoryRow(
                    title: "Storage Map",
                    detail: "Hierarchical squarified treemap of your largest folders",
                    systemImage: "chart.pie",
                    color: .teal,
                    totalBytes: store.scannedBytes,
                    reclaimableBytes: nil,
                    action: { store.selectedSection = .storage }
                )
            }
            .cleanerSurface()
        }
    }

    // MARK: - Largest Folders Section

    private var largestFoldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Largest Folders")
                    .font(.headline)
                Spacer()
                Button {
                    store.selectedSection = .storage
                } label: {
                    Text("View Full Treemap →")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 0) {
                ForEach(store.folderUsage.prefix(5), id: \.url) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(folder.url.lastPathComponent)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(folder.url.deletingLastPathComponent().path(percentEncoded: false))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(ByteCountFormatter.cleanerString(from: folder.bytes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button {
                            store.revealInFinder(forURL: folder.url)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reveal in Finder")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    if folder.url != store.folderUsage.prefix(5).last?.url {
                        Divider()
                    }
                }
            }
            .cleanerSurface()
        }
    }
}

// MARK: - Subviews

private struct LegendItem: View {
    let color: Color
    let title: String
    let size: Int64

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.cleanerString(from: size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct CategoryRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let totalBytes: Int64
    let reclaimableBytes: Int64?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.cleanerString(from: totalBytes))
                    .font(.subheadline.monospacedDigit())

                if let reclaim = reclaimableBytes, reclaim > 0 {
                    Text("\(ByteCountFormatter.cleanerString(from: reclaim)) reclaimable")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.cleanerSuccess)
                }
            }

            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct PermissionBanner: View {
    let items: [PermissionReadinessItem]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Permissions & Full Disk Access", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cleanerWarning)

                ForEach(items, id: \.id) { item in
                    Text("• \(item.title): \(item.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("System Settings…") {
                FullDiskAccess.openPrivacySettings()
            }
            .controlSize(.small)
        }
        .padding(12)
        .cleanerSubtleSurface()
    }
}
