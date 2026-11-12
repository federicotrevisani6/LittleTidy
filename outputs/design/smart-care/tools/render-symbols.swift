// Renders SF Symbols as black template PNGs so the HTML mockups can use them
// as CSS masks. The PNGs are generated locally and are not committed.
// Usage: swift render-symbols.swift <output-dir> <symbol> [<symbol> ...]
import AppKit

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for name in args.dropFirst(2) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else {
        FileHandle.standardError.write("missing symbol \(name)\n".data(using: .utf8)!); continue
    }
    let size = base.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width.rounded(.up)) + 8, pixelsHigh: Int(size.height.rounded(.up)) + 8,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.black.set()
    let r = NSRect(x: 4, y: 4, width: size.width, height: size.height)
    base.draw(in: r)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name + ".png"))
}
