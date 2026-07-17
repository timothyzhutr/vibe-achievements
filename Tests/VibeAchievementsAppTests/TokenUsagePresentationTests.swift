import XCTest
@testable import VibeAchievementsApp
import VibeAchievementsCore

final class TokenUsagePresentationTests: XCTestCase {
    func testCompactValueUsesReadableSuffixes() {
        XCTAssertEqual(TokenUsagePresentation.valueText(for: .init(totalTokens: 999, includesEstimates: false)), "999")
        XCTAssertEqual(TokenUsagePresentation.valueText(for: .init(totalTokens: 1_250, includesEstimates: false)), "1.3K")
        XCTAssertEqual(TokenUsagePresentation.valueText(for: .init(totalTokens: 1_250_000, includesEstimates: false)), "1.3M")
    }

    func testCompactValueMarksTotalsContainingEstimates() {
        XCTAssertEqual(
            TokenUsagePresentation.valueText(for: .init(totalTokens: 1_250, includesEstimates: true)),
            "≈1.3K"
        )
    }
}
