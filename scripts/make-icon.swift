#!/usr/bin/env swift
// Renders Resources/AppIcon.svg (the logo master) into Resources/AppIcon.icns, plus PNG exports of the
// icon for the website and README. Uses the system SVG renderer, so it needs nothing but macOS.
// Usage: swift scripts/make-icon.swift [--svg Resources/AppIcon.svg] [--icns Resources/AppIcon.icns] [--png-dir Resources/Brand]
import AppKit

var svgPath = "Resources/AppIcon.svg"
var icnsPath = "Resources/AppIcon.icns"
var pngDir: String? = "Resources/Brand"
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--svg": svgPath = args.removeFirst()
    case "--icns": icnsPath = args.removeFirst()
    case "--png-dir": pngDir = args.removeFirst()
    case "--no-png": pngDir = nil
    default: print("unknown argument \(a)"); exit(2)
    }
}

guard let master = NSImage(contentsOfFile: svgPath) else { print("cannot load \(svgPath)"); exit(1) }

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    writePNG(render(px), to: iconset.appendingPathComponent("icon_\(name).png").path)
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", icnsPath]
task.launch()
task.waitUntilExit()
guard task.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("Wrote \(icnsPath)")

if let pngDir {
    try! FileManager.default.createDirectory(atPath: pngDir, withIntermediateDirectories: true)
    for px in [1024, 512, 256, 128] {
        writePNG(render(px), to: "\(pngDir)/icon-\(px).png")
    }
    print("Wrote \(pngDir)/icon-{1024,512,256,128}.png")
}
