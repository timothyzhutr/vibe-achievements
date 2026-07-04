import AppKit
import XCTest
@testable import VibeAchievementsApp

final class LogoAssetTests: XCTestCase {
    func testMenuBarAndShelfMarksAreTemplateImages() {
        let menuBarImage = LogoAsset.statusBarImage()
        let shelfImage = LogoAsset.markImage(size: NSSize(width: 34, height: 34))

        XCTAssertTrue(menuBarImage.isTemplate)
        XCTAssertTrue(shelfImage.isTemplate)
        XCTAssertEqual(shelfImage.size, NSSize(width: 34, height: 34))
    }
}
