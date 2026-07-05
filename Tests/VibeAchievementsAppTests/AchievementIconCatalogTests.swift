import AppKit
import XCTest
@testable import VibeAchievementsApp
@testable import VibeAchievementsCore

final class AchievementIconCatalogTests: XCTestCase {
    func testEveryBundledAchievementHasAnExplicitIcon() throws {
        let contracts = try AchievementContractLoader.loadBundledV1()
        let missingIDs = contracts
            .map(\.id)
            .filter { AchievementIconCatalog.symbolName(for: $0) == AchievementIconCatalog.fallbackSymbolName }

        XCTAssertEqual(missingIDs, [])
    }

    func testBundledAchievementIconsResolveToSystemSymbols() throws {
        let contracts = try AchievementContractLoader.loadBundledV1()
        let unresolved = contracts
            .map { ($0.id, AchievementIconCatalog.symbolName(for: $0.id)) }
            .filter { NSImage(systemSymbolName: $0.1, accessibilityDescription: nil) == nil }
            .map { "\($0.0):\($0.1)" }

        XCTAssertEqual(unresolved, [])
    }

    func testKnownAchievementsUseDistinctRepresentativeSymbols() {
        XCTAssertEqual(AchievementIconCatalog.symbolName(for: "rm_rf"), "trash.slash")
        XCTAssertEqual(AchievementIconCatalog.symbolName(for: "one_more_prompt"), "text.bubble")
        XCTAssertEqual(AchievementIconCatalog.symbolName(for: "green_bar_acquired"), "checkmark.rectangle.stack")
    }
}
