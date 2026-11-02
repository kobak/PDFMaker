import AppKit

// Vector artwork built with macOS's own drawing APIs.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let preview = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
let fm = FileManager.default
let folder = fm.temporaryDirectory.appendingPathComponent("pdf-maker-\(UUID().uuidString).iconset")
try fm.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: folder) }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func sheet(x: CGFloat, y: CGFloat, label: String, tint: NSColor, detail: Bool) {
    let width: CGFloat = 278, height: CGFloat = 444, fold: CGFloat = 66
    let paper = NSBezierPath()
    paper.move(to: NSPoint(x: x + 24, y: y))
    paper.line(to: NSPoint(x: x + width - 24, y: y))
    paper.curve(to: NSPoint(x: x + width, y: y + 24), controlPoint1: NSPoint(x: x + width, y: y), controlPoint2: NSPoint(x: x + width, y: y))
    paper.line(to: NSPoint(x: x + width, y: y + height - fold))
    paper.line(to: NSPoint(x: x + width - fold, y: y + height))
    paper.line(to: NSPoint(x: x + 24, y: y + height))
    paper.curve(to: NSPoint(x: x, y: y + height - 24), controlPoint1: NSPoint(x: x, y: y + height), controlPoint2: NSPoint(x: x, y: y + height))
    paper.line(to: NSPoint(x: x, y: y + 24))
    paper.curve(to: NSPoint(x: x + 24, y: y), controlPoint1: NSPoint(x: x, y: y), controlPoint2: NSPoint(x: x, y: y))
    paper.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.10, 0.21, 0.40, 0.17)
    shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -15); shadow.set()
    NSColor.white.setFill(); paper.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0.79, 0.85, 0.93).setStroke(); paper.lineWidth = 3; paper.stroke()
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: x + width - fold, y: y + height))
    corner.line(to: NSPoint(x: x + width - fold, y: y + height - fold + 12))
    corner.curve(to: NSPoint(x: x + width - fold + 12, y: y + height - fold),
                 controlPoint1: NSPoint(x: x + width - fold, y: y + height - fold),
                 controlPoint2: NSPoint(x: x + width - fold, y: y + height - fold))
    corner.line(to: NSPoint(x: x + width, y: y + height - fold)); corner.close()
    color(0.88, 0.93, 0.99).setFill(); corner.fill()
    if detail {
        color(0.83, 0.88, 0.94).setStroke()
        for (index, length) in [CGFloat(125), CGFloat(172), CGFloat(145)].enumerated() {
            let line = NSBezierPath(), lineY = y + 313 - CGFloat(index) * 43
            line.move(to: NSPoint(x: x + 42, y: lineY)); line.line(to: NSPoint(x: x + 42 + length, y: lineY))
            line.lineWidth = 12; line.lineCapStyle = .round; line.stroke()
        }
    }
    let badge = NSRect(x: x - 14, y: y + 42, width: width + 28, height: 112)
    tint.setFill(); NSBezierPath(roundedRect: badge, xRadius: 22, yRadius: 22).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: detail ? 71 : 94, weight: .bold),
        .foregroundColor: NSColor.white, .kern: detail ? 1 : 0
    ]
    let text = (detail ? label : String(label.prefix(1))) as NSString
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
}

func render(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: color(0.97, 0.985, 1), ending: color(0.79, 0.87, 1))!.draw(in: background, angle: -70)
    color(1, 1, 1, 0.75).setStroke(); background.lineWidth = 4; background.stroke()
    sheet(x: 160, y: 294, label: "DOC", tint: color(0.13, 0.38, 0.83), detail: pixels > 32)
    sheet(x: 586, y: 244, label: "PDF", tint: color(0.91, 0.23, 0.28), detail: pixels > 32)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.12, 0.23, 0.44, 0.13)
    shadow.shadowBlurRadius = 12; shadow.shadowOffset = NSSize(width: 0, height: -6); shadow.set()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 466, y: 490)); arrow.line(to: NSPoint(x: 535, y: 490))
    arrow.line(to: NSPoint(x: 535, y: 450)); arrow.line(to: NSPoint(x: 601, y: 516))
    arrow.line(to: NSPoint(x: 535, y: 582)); arrow.line(to: NSPoint(x: 535, y: 542))
    arrow.line(to: NSPoint(x: 466, y: 542)); arrow.close()
    color(0.16, 0.25, 0.48).setFill(); arrow.fill()
    NSGraphicsContext.restoreGraphicsState(); NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let data = render(pixels: pixels).representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        if pixels == 1024, let preview { try data.write(to: preview) }
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", folder.path, "-o", destination.path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
