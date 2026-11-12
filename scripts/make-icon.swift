import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    let tile = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 188, yRadius: 188)
    NSGradient(starting: color(0x367563), ending: color(0x70B69C))!.draw(in: tile, angle: 55)
    NSShadow().set()
    color(0xFFFFFF).withAlphaComponent(0.12).setStroke()
    for x in stride(from: 294, through: 774, by: 120) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 267)); line.line(to: NSPoint(x: x, y: 775))
        line.lineWidth = 3; line.stroke()
    }
    let bars: [(NSRect, CGFloat)] = [
        (NSRect(x: 244, y: 658, width: 335, height: 76), 0.95),
        (NSRect(x: 364, y: 489, width: 416, height: 76), 0.8),
        (NSRect(x: 489, y: 320, width: 291, height: 76), 0.6)
    ]
    for (rect, alpha) in bars {
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 23, yRadius: 23).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [Int: [String]] = [16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"], 256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"]]
    for name in names[size]! { try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name)) }
}
