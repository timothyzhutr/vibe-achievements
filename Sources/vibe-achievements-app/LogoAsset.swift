import AppKit
import SwiftUI

enum LogoAsset {
    static func nsImage(size: NSSize? = nil) -> NSImage? {
        guard let url = Bundle.module.url(forResource: "VibeAchievementsLogo", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        if let size {
            image.size = size
        }
        image.isTemplate = false
        return image
    }

    static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let badge = NSBezierPath()
            badge.move(to: NSPoint(x: rect.midX, y: rect.maxY - 2.5))
            badge.line(to: NSPoint(x: rect.maxX - 3, y: rect.maxY - 6.5))
            badge.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 6.5))
            badge.line(to: NSPoint(x: rect.midX, y: rect.minY + 2.5))
            badge.line(to: NSPoint(x: rect.minX + 3, y: rect.minY + 6.5))
            badge.line(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 6.5))
            badge.close()
            badge.lineWidth = 1.7
            badge.stroke()

            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: 7.2, y: 6.1))
            chevron.line(to: NSPoint(x: 4.7, y: 9))
            chevron.line(to: NSPoint(x: 7.2, y: 11.9))
            chevron.lineWidth = 1.9
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 9.2, y: 12.1))
            cursor.line(to: NSPoint(x: 12.3, y: 12.1))
            cursor.lineWidth = 1.8
            cursor.lineCapStyle = .round
            cursor.stroke()

            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: 12.5, y: 5.1))
            sparkle.line(to: NSPoint(x: 12.5, y: 8.5))
            sparkle.move(to: NSPoint(x: 10.8, y: 6.8))
            sparkle.line(to: NSPoint(x: 14.2, y: 6.8))
            sparkle.lineWidth = 1.4
            sparkle.lineCapStyle = .round
            sparkle.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}

struct LogoMarkView: View {
    var size: CGFloat = 32

    var body: some View {
        if let image = LogoAsset.nsImage(size: NSSize(width: size, height: size)) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
