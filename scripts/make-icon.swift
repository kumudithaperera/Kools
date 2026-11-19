// Renders the Kools app icon (😆 on a dark rounded square) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let emoji = "😆"
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: an 824/1024 rounded square, centered.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.25, blue: 0.40, alpha: 1),
        ending: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.19, alpha: 1)
    )!.draw(in: path, angle: -90)

    let font = NSFont.systemFont(ofSize: tile.width * 0.62)
    let text = NSAttributedString(string: emoji, attributes: [.font: font])
    let textSize = text.size()
    text.draw(at: NSPoint(x: tile.midX - textSize.width / 2, y: tile.midY - textSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
