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

    func testLoadsBundledV1Contracts() throws {
        let contracts = try AchievementContractLoader.loadBundledV1()

        XCTAssertEqual(contracts.count, 50)
        XCTAssertTrue(contracts.contains { $0.id == "achievement_unlocked_unlocking_achievement" })
        XCTAssertTrue(contracts.contains { $0.id == "rm_rf" })
    }
}
