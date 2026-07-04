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

    func testThreadScopedAchievementUnlocksAgainInAnotherThreadSameProject() throws {
        let contracts = try loadSampleContracts()
        let correction = ["build me an app", "actually, wait, make it a CLI instead"]

        let threadA = transcript(threadID: "claude_code:A", projectKey: "/tmp/p", userTexts: correction)
        let unlocksA = AchievementEngine.evaluate(contracts: contracts, parsed: threadA, events: EventExtractor.extract(from: threadA))
        XCTAssertTrue(unlocksA.contains { $0.achievementID == "actually_wait" })

        // A second thread in the same project must still unlock the once_per_thread
        // achievement, since its scope is the thread, not the project.
        let threadB = transcript(threadID: "claude_code:B", projectKey: "/tmp/p", userTexts: correction)
        let unlocksB = AchievementEngine.evaluate(
            contracts: contracts,
            parsed: threadB,
            events: EventExtractor.extract(from: threadB),
            existingUnlockKeys: Set(unlocksA.map(\.unlockKey))
        )
        XCTAssertTrue(unlocksB.contains { $0.achievementID == "actually_wait" })
    }

    func testProjectScopedAchievementDoesNotRepeatInSameProject() throws {
        let contracts = try loadSampleContracts()
        let cleanup = ["build the app", "rm -rf node_modules please", "now reinstall everything"]

        let threadA = transcript(threadID: "claude_code:A", projectKey: "/tmp/p", userTexts: cleanup)
        let unlocksA = AchievementEngine.evaluate(contracts: contracts, parsed: threadA, events: EventExtractor.extract(from: threadA))
        XCTAssertTrue(unlocksA.contains { $0.achievementID == "rm_rf" })

        // rm_rf is once_per_project, so a different thread in the same project
        // must not unlock it again.
        let threadB = transcript(threadID: "claude_code:B", projectKey: "/tmp/p", userTexts: cleanup)
        let unlocksB = AchievementEngine.evaluate(
            contracts: contracts,
            parsed: threadB,
            events: EventExtractor.extract(from: threadB),
            existingUnlockKeys: Set(unlocksA.map(\.unlockKey))
        )
        XCTAssertFalse(unlocksB.contains { $0.achievementID == "rm_rf" })
    }

    private func loadSampleContracts() throws -> [AchievementContract] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        return try AchievementContractLoader.load(jsonlURL: url)
    }

    private func transcript(threadID: String, projectKey: String, userTexts: [String]) -> ParsedTranscript {
        let base = Date(timeIntervalSince1970: 1_000)
        let messages = userTexts.enumerated().map { index, text in
            NormalizedMessage(id: "\(threadID)-\(index)", threadID: threadID, sourceTool: .claudeCode, sourceMessageID: nil, role: .user, timestamp: base.addingTimeInterval(Double(index)), text: text, rawType: "user")
        }
        let thread = NormalizedThread(id: threadID, sourceTool: .claudeCode, sourceThreadID: threadID, sourcePath: "/tmp/\(threadID).jsonl", projectPath: projectKey, projectKey: projectKey, title: nil, createdAt: base, updatedAt: base, messageCount: messages.count, userTurnCount: messages.count, assistantTurnCount: 0, estimatedTokens: 1, rawTokenCount: nil)
        return ParsedTranscript(thread: thread, messages: messages)
    }
}
