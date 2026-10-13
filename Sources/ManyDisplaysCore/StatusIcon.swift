import AppKit

/// The menu bar glyph while tracking: the app's face (two displays as eyes, a keyboard as the mouth),
/// drawn as a template image so it follows the menu bar appearance. Mirrors `Resources/AppIcon.svg`.
enum StatusIcon {
    static func displays(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 15), flipped: true) { _ in
            NSColor.black.set()
            for x: CGFloat in [1, 10] {
                let screen = NSBezierPath(roundedRect: NSRect(x: x, y: 1.25, width: 7, height: 6), xRadius: 1.5, yRadius: 1.5)
                screen.lineWidth = 1.5
                screen.stroke()
                NSBezierPath(roundedRect: NSRect(x: x + 2.25, y: 3, width: 3, height: 2.5), xRadius: 0.5, yRadius: 0.5).fill()
                NSBezierPath(rect: NSRect(x: x + 2.75, y: 8, width: 1.5, height: 1.5)).fill()
                NSBezierPath(roundedRect: NSRect(x: x + 1.5, y: 9.5, width: 4, height: 1.25), xRadius: 0.625, yRadius: 0.625)
                    .fill()
            }
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 12.25, width: 11, height: 1.75), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
