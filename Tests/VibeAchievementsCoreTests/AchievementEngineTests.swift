import XCTest
@testable import VibeAchievementsCore

final class AchievementEngineTests: XCTestCase {
    func testUnlocksActuallyWaitAndRmRf() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)

        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let claude = try ClaudeCodeParser.parse(fileURL: claudeURL)
        let claudeUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: claude, events: EventExtractor.extract(from: claude), existingUnlockKeys: ["achievement_unlocked_unlocking_achievement"])

        let codexURL = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let codex = try CodexParser.parse(fileURL: codexURL)
        let codexUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: codex, events: EventExtractor.extract(from: codex), existingUnlockKeys: ["achievement_unlocked_unlocking_achievement"])

        XCTAssertTrue(claudeUnlocks.contains { $0.achievementID == "actually_wait" })
        XCTAssertTrue(codexUnlocks.contains { $0.achievementID == "rm_rf" })
    }

    func testAlreadyUnlockedKeysAreNotReEmitted() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)

        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let claude = try ClaudeCodeParser.parse(fileURL: claudeURL)
        let events = EventExtractor.extract(from: claude)

        let firstPass = AchievementEngine.evaluate(contracts: contracts, parsed: claude, events: events)
        XCTAssertTrue(firstPass.contains { $0.achievementID == "actually_wait" })

        // Feeding the prior unlock keys back in must suppress a re-unlock.
        let secondPass = AchievementEngine.evaluate(
            contracts: contracts,
            parsed: claude,
            events: events,
            existingUnlockKeys: Set(firstPass.map(\.unlockKey))
        )
        XCTAssertTrue(secondPass.isEmpty)
    }
}
