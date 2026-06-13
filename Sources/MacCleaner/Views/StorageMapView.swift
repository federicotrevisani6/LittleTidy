import MacCleanerCore
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

    private var totalBytes: Int64 {
        store.folderUsage.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Storage Map")
                    .font(.largeTitle.weight(.semibold))
                Text("Top folders by size across the scanned roots. Tap a tile to reveal it in Finder.")
                    .foregroundStyle(.secondary)
            }

            if store.folderUsage.isEmpty {
                ContentUnavailableView(
                    "No Storage Data",
                    systemImage: "square.grid.2x2",
                    description: Text("Run a scan to see where space is used.")
                )
                .frame(maxWidth: .infinity)
                .padding(24)
                .cleanerSurface()
            } else {
                HStack {
                    Text("\(store.folderUsage.count) folders")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(ByteCountFormatter.cleanerString(from: totalBytes)) scanned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    let weights = store.folderUsage.map { Double($0.bytes) }
                    let rects = TreemapLayout.rects(forWeights: weights, in: bounds)

                    ZStack(alignment: .topLeading) {
                        ForEach(Array(store.folderUsage.enumerated()), id: \.element.id) { index, folder in
                            TreemapTile(
                                folder: folder,
                                fraction: totalBytes > 0 ? Double(folder.bytes) / Double(totalBytes) : 0,
                                rank: index,
                                count: store.folderUsage.count
                            ) {
                                store.revealInFinder(forURL: folder.url)
                            }
                            .frame(width: max(0, rects[index].width - 2), height: max(0, rects[index].height - 2))
                            .offset(x: rects[index].minX, y: rects[index].minY)
                        }
                    }
                }
                .frame(height: 460)
                .cleanerSurface()
            }
        }
    }
}

private struct TreemapTile: View {
    let folder: FolderUsage
    let fraction: Double
    let rank: Int
    let count: Int
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tileColor)

                GeometryReader { proxy in
                    if proxy.size.width > 60, proxy.size.height > 34 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(ByteCountFormatter.cleanerString(from: folder.bytes))
                                .font(.caption2)
                                .opacity(0.85)
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
    }

    /// Largest folders are the most saturated; smaller ones fade toward neutral.
    private var tileColor: Color {
        let progress = count > 1 ? Double(rank) / Double(count - 1) : 0
        return Color(hue: 0.58, saturation: 0.85 - progress * 0.55, brightness: 0.55 + progress * 0.2)
    }
}
