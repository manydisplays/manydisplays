#!/usr/bin/env swift
// Draws the DMG window background (Resources/DMG/background.tiff, 1x + 2x): navy like the
// website's dark theme, the wordmark, an orange arrow from the app to Applications and a hint.
// Finder draws the icon names in black over a background picture (in Dark Mode too), so each
// name sits on a light pill. Finder's status bar, when the user has it on, covers the bottom
// ~24 pt, so nothing important goes there. Icon centres must match scripts/dmg-settings.py.
// Usage: swift scripts/make-dmg-background.swift [--out Resources/DMG/background.tiff]
import AppKit

var out = "Resources/DMG/background.tiff"
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": out = args.removeFirst()
    default: print("unknown argument \(a)"); exit(2)
    }
}

let size = NSSize(width: 640, height: 400)
let app = NSPoint(x: 170, y: 200), apps = NSPoint(x: 470, y: 200), iconSize: CGFloat = 112

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
        green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func text(
    _ string: String,
    size: CGFloat,
    weight: NSFont.Weight,
    colour: NSColor,
    centreX: CGFloat,
    top: CGFloat,
    kern: CGFloat = 0
) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributed = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: colour,
        .paragraphStyle: style,
        .kern: kern,
    ])
    let height = attributed.size().height
    attributed.draw(in: NSRect(x: centreX - 300, y: top, width: 600, height: height))
}

/// Everything is drawn in a flipped context: y grows downwards, like Finder's icon positions.
func draw() {
    // Background: navy with a soft warm glow behind the arrow.
    NSGradient(colors: [colour(0x1A1D33), colour(0x121426)])!.draw(in: NSRect(origin: .zero, size: size), angle: 90)
    NSGradient(colors: [colour(0xFF9F43, 0.16), colour(0xFF9F43, 0)])!
        .draw(fromCenter: NSPoint(x: 320, y: 200), radius: 0, toCenter: NSPoint(x: 320, y: 200), radius: 230, options: [])

    // Slots: a faint rounded square behind each icon and a pill under it for the name.
    for centre in [app, apps] {
        let slot = NSRect(x: centre.x - 80, y: centre.y - 76, width: 160, height: 174)
        colour(0xFFFFFF, 0.04).setFill()
        NSBezierPath(roundedRect: slot, xRadius: 26, yRadius: 26).fill()
        colour(0xFFFFFF, 0.08).setStroke()
        let border = NSBezierPath(roundedRect: slot.insetBy(dx: 0.5, dy: 0.5), xRadius: 26, yRadius: 26)
        border.lineWidth = 1
        border.stroke()
        // Finder centres the 13 pt name about 17 pt under the icon's bottom edge (measured).
        let pill = NSRect(x: centre.x - 62, y: centre.y + iconSize / 2 + 5, width: 124, height: 24)
        colour(0xE9E6DF).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
    }

    // Arrow: a gentle arc from the app to Applications in the icon's orange gradient.
    let start = NSPoint(x: app.x + 92, y: app.y), end = NSPoint(x: apps.x - 100, y: apps.y)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(
        to: end,
        controlPoint1: NSPoint(x: start.x + 40, y: start.y - 34),
        controlPoint2: NSPoint(x: end.x - 40, y: end.y - 34)
    )
    arc.lineWidth = 6
    arc.lineCapStyle = .round
    // The head follows the curve's direction at its end (from the last control point).
    let dx: CGFloat = 40, dy: CGFloat = 34, length = (dx * dx + dy * dy).squareRoot()
    let ux = dx / length, uy = dy / length
    let back = NSPoint(x: end.x - 16 * ux, y: end.y - 16 * uy)
    let head = NSBezierPath()
    head.move(to: NSPoint(x: back.x + 11 * uy, y: back.y - 11 * ux))
    head.line(to: end)
    head.line(to: NSPoint(x: back.x - 11 * uy, y: back.y + 11 * ux))
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    for path in [arc, head] {
        ctx.addPath(path.cgPath)
    }
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let warm = NSGradient(colors: [colour(0xFFD166), colour(0xFF9F43)])!
    warm.draw(in: NSRect(x: start.x - 4, y: start.y - 40, width: end.x - start.x + 12, height: 60), angle: 0)
    ctx.restoreGState()

    text("Many Displays", size: 26, weight: .bold, colour: colour(0xF3F2EE), centreX: 320, top: 34, kern: -0.3)
    text(
        "Drag the app into Applications to install it",
        size: 13,
        weight: .regular,
        colour: colour(0xA9ACC0),
        centreX: 320,
        top: 70
    )
    text(
        "Then open it from Applications. It lives in your menu bar.",
        size: 11,
        weight: .regular,
        colour: colour(0xA9ACC0, 0.8),
        centreX: 320,
        top: 334
    )
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    // The context already maps points to pixels (rep.size is in points); only flip it.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: out).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try tiff.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
