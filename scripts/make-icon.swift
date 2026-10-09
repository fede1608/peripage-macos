// Draws the app icon into an .iconset folder: swiftc make-icon.swift -o make-icon && ./make-icon out.iconset
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        let ctx = NSGraphicsContext.current!.cgContext

        // Background squircle.
        let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.45, alpha: 1),
                   ending: NSColor(calibratedRed: 0.93, green: 0.33, blue: 0.42, alpha: 1))!.draw(in: bg, angle: -90)

        // Paper strip coming out of the printer.
        let paper = NSBezierPath(roundedRect: NSRect(x: 330 * s, y: 190 * s, width: 364 * s, height: 470 * s), xRadius: 18 * s, yRadius: 18 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
        paper.fill()
        ctx.restoreGState()

        // Dithered heart on the paper.
        let heart = NSBezierPath()
        let cx = 512 * s, cy = 420 * s, r = 62 * s
        heart.move(to: NSPoint(x: cx, y: cy - 1.9 * r))
        heart.curve(to: NSPoint(x: cx - 2.1 * r, y: cy + 0.4 * r), controlPoint1: NSPoint(x: cx - 1.0 * r, y: cy - 1.2 * r), controlPoint2: NSPoint(x: cx - 2.1 * r, y: cy - 0.6 * r))
        heart.curve(to: NSPoint(x: cx, y: cy + 0.9 * r), controlPoint1: NSPoint(x: cx - 2.1 * r, y: cy + 1.6 * r), controlPoint2: NSPoint(x: cx - 0.5 * r, y: cy + 1.9 * r))
        heart.curve(to: NSPoint(x: cx + 2.1 * r, y: cy + 0.4 * r), controlPoint1: NSPoint(x: cx + 0.5 * r, y: cy + 1.9 * r), controlPoint2: NSPoint(x: cx + 2.1 * r, y: cy + 1.6 * r))
        heart.curve(to: NSPoint(x: cx, y: cy - 1.9 * r), controlPoint1: NSPoint(x: cx + 2.1 * r, y: cy - 0.6 * r), controlPoint2: NSPoint(x: cx + 1.0 * r, y: cy - 1.2 * r))
        ctx.saveGState()
        heart.addClip()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        let dot = 15 * s
        var y = cy - 2 * r
        var row = 0
        while y < cy + 2 * r {
            var x = cx - 2.2 * r + (row % 2 == 0 ? 0 : dot / 2)
            while x < cx + 2.2 * r {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot * 0.78, height: dot * 0.78)).fill()
                x += dot
            }
            y += dot * 0.87
            row += 1
        }
        ctx.restoreGState()

        // Text lines.
        NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 395 * s, y: 255 * s, width: 234 * s, height: 16 * s), xRadius: 8 * s, yRadius: 8 * s).fill()
        NSBezierPath(roundedRect: NSRect(x: 430 * s, y: 222 * s, width: 164 * s, height: 16 * s), xRadius: 8 * s, yRadius: 8 * s).fill()

        // Printer body.
        let body = NSBezierPath(roundedRect: NSRect(x: 230 * s, y: 590 * s, width: 564 * s, height: 230 * s), xRadius: 70 * s, yRadius: 70 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        body.fill()
        ctx.restoreGState()
        // Slot.
        NSColor(calibratedWhite: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 310 * s, y: 640 * s, width: 404 * s, height: 26 * s), xRadius: 13 * s, yRadius: 13 * s).fill()
        // Light.
        NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.55, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 700 * s, y: 730 * s, width: 34 * s, height: 34 * s)).fill()
        return true
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let image = drawIcon(size: CGFloat(px))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
