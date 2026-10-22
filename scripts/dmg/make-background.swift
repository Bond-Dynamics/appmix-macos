// Draws the DMG window background: an arrow from the app's slot to the Applications slot and a
// one-line instruction. Slot positions must match `icon_locations` in scripts/dmg/settings.py.
// Usage: swift scripts/dmg/make-background.swift <out-dir>
//        tiffutil -cathidpicheck <out-dir>/background.png <out-dir>/background@2x.png -out scripts/dmg/background.tiff
import AppKit

/// Window content size in points (`window_rect` in settings.py).
private let size = CGSize(width: 640, height: 400)
/// Icon centres in points, measured from the TOP-left as Finder does (settings.py `icon_locations`).
private let appSlot = CGPoint(x: 170, y: 190)
private let applicationsSlot = CGPoint(x: 470, y: 190)
private let instruction = "Drag AppMix to Applications to install"

private func draw(in context: CGContext) {
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedWhite: 0.985, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
    drawArrow(in: context)
    drawInstruction()
}

/// Core Graphics draws from the bottom-left, Finder places icons from the top-left.
private func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: size.height - point.y) }

private func drawArrow(in context: CGContext) {
    let iconHalfWidth: CGFloat = 80
    let start = CGPoint(x: flipped(appSlot).x + iconHalfWidth, y: flipped(appSlot).y)
    let end = CGPoint(x: flipped(applicationsSlot).x - iconHalfWidth, y: flipped(applicationsSlot).y)
    let color = NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.48, alpha: 0.55).cgColor
    let headLength: CGFloat = 22

    context.setStrokeColor(color)
    context.setLineWidth(6)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [2, 14])
    context.move(to: start)
    context.addLine(to: CGPoint(x: end.x - headLength, y: end.y))
    context.strokePath()

    context.setLineDash(phase: 0, lengths: [])
    context.setFillColor(color)
    context.move(to: end)
    context.addLine(to: CGPoint(x: end.x - headLength, y: end.y + 15))
    context.addLine(to: CGPoint(x: end.x - headLength, y: end.y - 15))
    context.closePath()
    context.fillPath()
}

private func drawInstruction() {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.29, blue: 0.38, alpha: 1),
    ]
    let text = NSAttributedString(string: instruction, attributes: attributes)
    let textSize = text.size()
    text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: 62))
}

private func writePNG(scale: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                                     pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        throw NSError(domain: "make-background", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bitmap at \(scale)x"])
    }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let context = NSGraphicsContext.current?.cgContext { draw(in: context) }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-background", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed at \(scale)x"])
    }
    try data.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-background.swift <out-dir>\n".utf8))
    exit(64)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try writePNG(scale: 1, to: outDir.appendingPathComponent("background.png"))
try writePNG(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
print("Wrote \(outDir.path)/background.png and background@2x.png")
