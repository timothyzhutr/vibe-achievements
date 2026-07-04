import XCTest
@testable import VibeAchievementsCore

final class AchievementContractTests: XCTestCase {
    func testLoadsJSONLContracts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: url)

        XCTAssertEqual(contracts.count, 2)
        XCTAssertEqual(contracts.first?.id, "actually_wait")
        XCTAssertEqual(contracts.last?.name, "rm -rf")
        XCTAssertTrue(contracts.allSatisfy(\.active))
    }
}
