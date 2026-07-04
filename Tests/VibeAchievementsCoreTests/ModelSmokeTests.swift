import XCTest
@testable import VibeAchievementsCore

final class ModelSmokeTests: XCTestCase {
    func testProjectKeyNormalizesPath() {
        XCTAssertEqual(
            projectKey(for: "/Users/Timothy/Documents/Cross Platform LLM App"),
            "/users/timothy/documents/cross-platform-llm-app"
        )
    }
}
