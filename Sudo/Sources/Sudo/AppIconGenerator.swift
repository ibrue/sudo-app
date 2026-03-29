import Cocoa

/// Generates the app icon programmatically for the Dock.
/// Draws white "[]" brackets on a black rounded-rect background.
enum AppIconGenerator {
    static func makeIcon(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.223 // ~228/1024, matches macOS icon shape

        // Black rounded-rect background
        let bg = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.black.setFill()
        bg.fill()

        // Bracket geometry (proportional to 1024 grid)
        let s = size / 1024.0
        NSColor.white.setFill()

        // Left bracket [
        let left = NSBezierPath()
        left.move(to: NSPoint(x: 290 * s, y: (1024 - 240) * s))
        left.line(to: NSPoint(x: 450 * s, y: (1024 - 240) * s))
        left.line(to: NSPoint(x: 450 * s, y: (1024 - 320) * s))
        left.line(to: NSPoint(x: 370 * s, y: (1024 - 320) * s))
        left.line(to: NSPoint(x: 370 * s, y: (1024 - 704) * s))
        left.line(to: NSPoint(x: 450 * s, y: (1024 - 704) * s))
        left.line(to: NSPoint(x: 450 * s, y: (1024 - 784) * s))
        left.line(to: NSPoint(x: 290 * s, y: (1024 - 784) * s))
        left.close()
        left.fill()

        // Right bracket ]
        let right = NSBezierPath()
        right.move(to: NSPoint(x: 574 * s, y: (1024 - 240) * s))
        right.line(to: NSPoint(x: 734 * s, y: (1024 - 240) * s))
        right.line(to: NSPoint(x: 734 * s, y: (1024 - 784) * s))
        right.line(to: NSPoint(x: 574 * s, y: (1024 - 784) * s))
        right.line(to: NSPoint(x: 574 * s, y: (1024 - 704) * s))
        right.line(to: NSPoint(x: 654 * s, y: (1024 - 704) * s))
        right.line(to: NSPoint(x: 654 * s, y: (1024 - 320) * s))
        right.line(to: NSPoint(x: 574 * s, y: (1024 - 320) * s))
        right.close()
        right.fill()

        image.unlockFocus()
        return image
    }
}
