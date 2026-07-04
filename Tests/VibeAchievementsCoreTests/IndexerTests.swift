import XCTest
@testable import VibeAchievementsCore

final class IndexerTests: XCTestCase {
    func testUnreadableFileIsReportedNotSilentlyDropped() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
        let storePath = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"

        // A .jsonl path that does not exist: parsing must fail, and the file
        // must be reported as a warning rather than vanishing.
        let missing = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")

        let result = try Indexer.index(paths: [missing], contracts: contracts, storePath: storePath)

        XCTAssertTrue(result.unlocks.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.path, missing.path)
    }

    func testValidTranscriptStillIndexesAlongsideWarnings() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let missing = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")
        let storePath = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"

        let result = try Indexer.index(paths: [claudeURL, missing], contracts: contracts, storePath: storePath)

        XCTAssertTrue(result.unlocks.contains { $0.achievementID == "actually_wait" })
        XCTAssertEqual(result.warnings.count, 1)
    }
}
