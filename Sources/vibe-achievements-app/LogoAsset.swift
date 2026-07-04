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
