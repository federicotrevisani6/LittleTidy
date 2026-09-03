import LittleTidyCore
import SwiftUI

/// Row-based squarified treemap layout. Pure geometry so it can be unit-tested
/// independently of SwiftUI rendering.
enum TreemapLayout {
    /// Returns one rect per weight, in input order, tiling `bounds` with area
    /// proportional to each weight. Weights are expected sorted largest-first.
    static func rects(forWeights weights: [Double], in bounds: CGRect) -> [CGRect] {
        let count = weights.count
        guard count > 0, bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: count)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: .zero, count: count)
        }

        let totalArea = Double(bounds.width) * Double(bounds.height)
        let areas = weights.map { $0 / total * totalArea }

        var result = Array(repeating: CGRect.zero, count: count)
        var free = bounds
        var start = 0

        while start < count {
            let side = Double(min(free.width, free.height))

            // Grow the current row while the worst aspect ratio keeps improving.
            var end = start + 1
            var rowAreas = [areas[start]]
            var worst = worstAspect(rowAreas, side: side)
            while end < count {
                let candidate = rowAreas + [areas[end]]
                let candidateWorst = worstAspect(candidate, side: side)
                if candidateWorst > worst {
                    break
                }
                rowAreas = candidate
                worst = candidateWorst
                end += 1
            }

            let rowArea = rowAreas.reduce(0, +)
            let thickness = CGFloat(rowArea / side)

            if free.width >= free.height {
                // Vertical strip on the left; items stacked top-to-bottom.
                var y = free.minY
                for index in start..<end {
                    let height = CGFloat(areas[index] / rowArea) * free.height
                    result[index] = CGRect(x: free.minX, y: y, width: thickness, height: height)
                    y += height
                }
                free = CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
            } else {
                // Horizontal strip on top; items placed left-to-right.
                var x = free.minX
                for index in start..<end {
                    let width = CGFloat(areas[index] / rowArea) * free.width
                    result[index] = CGRect(x: x, y: free.minY, width: width, height: thickness)
                    x += width
                }
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
            }
            start = end
        }
        return result
    }

    private static func worstAspect(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0 else {
            return .infinity
        }
        let thickness = sum / side
        var worst = 0.0
        for area in areas {
            let length = area / thickness
            guard length > 0 else {
                return .infinity
            }
            worst = max(worst, max(thickness / length, length / thickness))
        }
        return worst
    }
}

struct StorageMapView: View {
    @ObservedObject var store: ScanReviewStore
    @State private var currentRootFolderURL: URL?
    @State private var hoveredFolderID: URL?

    private var displayedFolders: [FolderUsage] {
        if let current = currentRootFolderURL {
            let prefix = current.standardizedFileURL.path
            return store.folderUsage.filter { folder in
                let folderPath = folder.url.standardizedFileURL.path
                return folderPath.hasPrefix(prefix + "/") || folderPath == prefix
            }
        }
        return store.folderUsage
    }

    private var totalBytes: Int64 {
        displayedFolders.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Storage Map")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        if currentRootFolderURL != nil {
                            Button {
                                currentRootFolderURL = nil
                            } label: {
                                Label("Back to Overview", systemImage: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if let current = currentRootFolderURL {
                        HStack(spacing: 6) {
                            Button("All Folders") {
                                currentRootFolderURL = nil
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)

                            Text("/")
                                .foregroundStyle(.tertiary)

                            Text(current.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                        }
                        .font(.subheadline)
                    } else {
                        Text("Interactive squarified treemap of your largest scanned folders. Click any tile to inspect or reveal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            if store.folderUsage.isEmpty {
                ContentUnavailableView(
                    "No Storage Data",
                    systemImage: "square.grid.2x2",
                    description: Text("Run a scan to see where your disk space is used.")
                )
                .frame(maxWidth: .infinity)
                .padding(24)
                .cleanerSurface()
            } else {
                HStack {
                    Text("\(displayedFolders.count) folders")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(ByteCountFormatter.cleanerString(from: totalBytes)) mapped")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    let weights = displayedFolders.map { Double($0.bytes) }
                    let rects = TreemapLayout.rects(forWeights: weights, in: bounds)

                    ZStack(alignment: .topLeading) {
                        ForEach(Array(displayedFolders.enumerated()), id: \.element.id) { index, folder in
                            TreemapTile(
                                folder: folder,
                                fraction: totalBytes > 0 ? Double(folder.bytes) / Double(totalBytes) : 0,
                                rank: index,
                                count: displayedFolders.count,
                                isHovered: hoveredFolderID == folder.url,
                                onSelect: {
                                    if currentRootFolderURL == folder.url {
                                        store.revealInFinder(forURL: folder.url)
                                    } else {
                                        currentRootFolderURL = folder.url
                                    }
                                },
                                onReveal: {
                                    store.revealInFinder(forURL: folder.url)
                                }
                            )
                            .frame(width: max(0, rects[index].width - 2), height: max(0, rects[index].height - 2))
                            .offset(x: rects[index].minX, y: rects[index].minY)
                            .onHover { isHovering in
                                hoveredFolderID = isHovering ? folder.url : nil
                            }
                        }
                    }
                }
                .frame(height: 440)
                .cleanerSurface()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(currentRootFolderURL == nil ? "Largest Scanned Folders" : "Subfolders in \(currentRootFolderURL?.lastPathComponent ?? "")")
                            .font(.headline)
                        Spacer()
                    }

                    ForEach(displayedFolders.prefix(12)) { folder in
                        StorageFolderRow(
                            folder: folder,
                            totalBytes: totalBytes,
                            onDrillDown: {
                                currentRootFolderURL = folder.url
                            },
                            reveal: {
                                store.revealInFinder(forURL: folder.url)
                            }
                        )
                    }
                }
                .padding(16)
                .cleanerSurface()
            }
        }
        .padding(24)
    }
}
}

private struct TreemapTile: View {
    let folder: FolderUsage
    let fraction: Double
    let rank: Int
    let count: Int
    let isHovered: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tileColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isHovered ? Color.white.opacity(0.6) : Color.clear, lineWidth: 2)
                    )

                GeometryReader { proxy in
                    if proxy.size.width > 55, proxy.size.height > 32 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(ByteCountFormatter.cleanerString(from: folder.bytes))
                                .font(.caption2)
                                .opacity(0.9)
                        }
                        .padding(6)
                        .foregroundStyle(.white)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(folder.name) — \(ByteCountFormatter.cleanerString(from: folder.bytes)) (\(folder.fileCount) files)")
        .contextMenu {
            Button {
                onReveal()
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
            Button {
                onSelect()
            } label: {
                Label("Focus Folder", systemImage: "scope")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
            }
        }
    }

    private var tileColor: Color {
        let progress = count > 1 ? Double(rank) / Double(count - 1) : 0
        return Color(hue: 0.58, saturation: 0.85 - progress * 0.5, brightness: 0.55 + progress * 0.2)
    }
}

private struct StorageFolderRow: View {
    let folder: FolderUsage
    let totalBytes: Int64
    let onDrillDown: () -> Void
    let reveal: () -> Void

    private var share: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return Double(folder.bytes) / Double(totalBytes)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(folder.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer()

            HStack(spacing: 12) {
                Text("\(folder.fileCount) files")
                Text(share.formatted(.percent.precision(.fractionLength(0...1))))
                Text(ByteCountFormatter.cleanerString(from: folder.bytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                reveal()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Reveal in Finder", action: reveal)
            Button("Focus Folder", action: onDrillDown)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder.url.path, forType: .string)
            }
        }
    }
}
