// Draws the AppMix icon (a mixer: three sliders on a rounded tile) at every size an .icns needs.
// Usage: swift scripts/icon/make-icon.swift <output.iconset>
//        iconutil -c icns <output.iconset> -o Resources/AppIcon.icns
import AppKit

private let canvas: CGFloat = 1024
/// macOS icon grid: the tile is 824 pt inside a 1024 canvas, leaving room for the system shadow.
private let tileInset: CGFloat = 100
private let tileCornerRadius: CGFloat = 185
private let topColor = NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.55, alpha: 1)
private let bottomColor = NSColor(calibratedRed: 0.09, green: 0.55, blue: 0.62, alpha: 1)
/// Knob height on each track, as a fraction from bottom to top.
private let knobPositions: [CGFloat] = [0.32, 0.72, 0.50]

private func drawIcon(in context: CGContext) {
    let tile = CGRect(x: tileInset, y: tileInset, width: canvas - 2 * tileInset, height: canvas - 2 * tileInset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileCornerRadius, cornerHeight: tileCornerRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(tilePath)
    context.setFillColor(bottomColor.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [bottomColor.cgColor, topColor.cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    drawSliders(in: context, tile: tile)
    context.restoreGState()
}

private func drawSliders(in context: CGContext, tile: CGRect) {
    let trackWidth: CGFloat = 36
    let trackTop = tile.maxY - 170
    let trackBottom = tile.minY + 170
    let spacing = tile.width / CGFloat(knobPositions.count + 1)
    for (index, position) in knobPositions.enumerated() {
        let x = tile.minX + spacing * CGFloat(index + 1)
        let track = CGRect(x: x - trackWidth / 2, y: trackBottom, width: trackWidth, height: trackTop - trackBottom)
        context.addPath(CGPath(roundedRect: track, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil))
        context.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        context.fillPath()

        let knobY = trackBottom + (trackTop - trackBottom) * position
        let filled = CGRect(x: track.minX, y: trackBottom, width: trackWidth, height: knobY - trackBottom)
        context.addPath(CGPath(roundedRect: filled, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil))
        context.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.fillPath()

        let knob = CGRect(x: x - 62, y: knobY - 40, width: 124, height: 80)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        context.addPath(CGPath(roundedRect: knob, cornerWidth: 40, cornerHeight: 40, transform: nil))
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()
    }
}

private func writePNG(pixels: Int, to url: URL) throws {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bitmap context at \(pixels) px"])
    }
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed at \(pixels) px"])
    }
    try data.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(64)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try writePNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("Wrote \(iconset.path)")
