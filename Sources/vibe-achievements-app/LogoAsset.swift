import AppKit
import SwiftUI

enum LogoAsset {
    static func statusBarImage() -> NSImage {
        markImage(size: NSSize(width: 18, height: 18))
    }

    static func markImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let length = min(rect.width, rect.height)
            let xOffset = rect.midX - length / 2
            let yOffset = rect.midY - length / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: xOffset + length * (x / 18),
                    y: yOffset + length * (y / 18)
                )
            }

            func scaled(_ value: CGFloat) -> CGFloat {
                length * (value / 18)
            }

            NSColor.black.setStroke()
            let badge = NSBezierPath()
            badge.move(to: point(9, 15.5))
            badge.line(to: point(15, 11.5))
            badge.line(to: point(15, 6.5))
            badge.line(to: point(9, 2.5))
            badge.line(to: point(3, 6.5))
            badge.line(to: point(3, 11.5))
            badge.close()
            badge.lineWidth = scaled(1.7)
            badge.stroke()

            let chevron = NSBezierPath()
            chevron.move(to: point(7.2, 6.1))
            chevron.line(to: point(4.7, 9))
            chevron.line(to: point(7.2, 11.9))
            chevron.lineWidth = scaled(1.9)
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: point(9.2, 12.1))
            cursor.line(to: point(12.3, 12.1))
            cursor.lineWidth = scaled(1.8)
            cursor.lineCapStyle = .round
            cursor.stroke()

            let sparkle = NSBezierPath()
            sparkle.move(to: point(12.5, 5.1))
            sparkle.line(to: point(12.5, 8.5))
            sparkle.move(to: point(10.8, 6.8))
            sparkle.line(to: point(14.2, 6.8))
            sparkle.lineWidth = scaled(1.4)
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
        Image(nsImage: LogoAsset.markImage(size: NSSize(width: size, height: size)))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}
