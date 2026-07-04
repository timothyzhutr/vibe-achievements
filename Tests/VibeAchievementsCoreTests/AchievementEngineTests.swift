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

    func testAchievementDoesNotUnlockAgainInAnotherThread() throws {
        let contracts = try loadSampleContracts()
        let correction = ["build me an app", "actually, wait, make it a CLI instead"]

        let threadA = transcript(threadID: "claude_code:A", projectKey: "/tmp/p", userTexts: correction)
        let unlocksA = AchievementEngine.evaluate(contracts: contracts, parsed: threadA, events: EventExtractor.extract(from: threadA))
        XCTAssertTrue(unlocksA.contains { $0.achievementID == "actually_wait" })

        let threadB = transcript(threadID: "claude_code:B", projectKey: "/tmp/other-project", userTexts: correction)
        let unlocksB = AchievementEngine.evaluate(
            contracts: contracts,
            parsed: threadB,
            events: EventExtractor.extract(from: threadB),
            existingUnlockKeys: Set(unlocksA.map(\.unlockKey))
        )
        XCTAssertFalse(unlocksB.contains { $0.achievementID == "actually_wait" })
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

    func testItWorksRequiresImplementationOrFixBeforeSuccess() throws {
        let contracts = [itWorksContract()]

        let successOnly = transcript(threadID: "claude_code:success", projectKey: "/tmp/p", userTexts: ["it works now"])
        XCTAssertFalse(AchievementEngine
            .evaluate(contracts: contracts, parsed: successOnly, events: EventExtractor.extract(from: successOnly))
            .contains { $0.achievementID == "it_works_therefore_it_is" })

        let successThenImplementation = transcript(threadID: "claude_code:reverse", projectKey: "/tmp/p", userTexts: ["it works now", "please implement the menu"])
        XCTAssertFalse(AchievementEngine
            .evaluate(contracts: contracts, parsed: successThenImplementation, events: EventExtractor.extract(from: successThenImplementation))
            .contains { $0.achievementID == "it_works_therefore_it_is" })

        let implementationThenSuccess = transcript(threadID: "claude_code:ordered", projectKey: "/tmp/p", userTexts: ["please implement the menu", "it works now"])
        XCTAssertTrue(AchievementEngine
            .evaluate(contracts: contracts, parsed: implementationThenSuccess, events: EventExtractor.extract(from: implementationThenSuccess))
            .contains { $0.achievementID == "it_works_therefore_it_is" })
    }

    func testMetaAchievementRequiresARealUnlock() throws {
        let contracts = [metaContract(), actuallyWaitContract()]

        let noMatch = transcript(threadID: "claude_code:quiet", projectKey: "/tmp/p", userTexts: ["hello there"])
        XCTAssertTrue(AchievementEngine
            .evaluate(contracts: contracts, parsed: noMatch, events: EventExtractor.extract(from: noMatch))
            .isEmpty)

        let firstRealUnlock = transcript(threadID: "claude_code:correction", projectKey: "/tmp/p", userTexts: ["build the app", "actually make it a CLI"])
        XCTAssertEqual(
            Set(AchievementEngine
                .evaluate(contracts: contracts, parsed: firstRealUnlock, events: EventExtractor.extract(from: firstRealUnlock))
                .map(\.achievementID)),
            ["actually_wait", "achievement_unlocked_unlocking_achievement"]
        )
    }

    private func loadSampleContracts() throws -> [AchievementContract] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        return try AchievementContractLoader.load(jsonlURL: url)
    }

    private func itWorksContract() -> AchievementContract {
        AchievementContract(
            id: "it_works_therefore_it_is",
            number: 29,
            name: "It Works, Therefore It Is",
            category: "vibe_coding_memes",
            definition: "Implementation or fix language is followed by success language.",
            detectionClass: "sequence",
            signals: ["implementation_or_fix_terms_seen", "success_terms_seen_later"],
            window: "same_thread",
            exclusions: [],
            cooldown: "once_per_thread",
            confidence: "high",
            status: "keep",
            difficulty: "starter",
            expectedFrequency: "weekly",
            active: true
        )
    }

    private func metaContract() -> AchievementContract {
        AchievementContract(
            id: "achievement_unlocked_unlocking_achievement",
            number: 1,
            name: "Achievement Unlocked: Unlocking Achievement",
            category: "meta",
            definition: "The first achievement unlocks.",
            detectionClass: "metadata",
            signals: ["first_achievement_unlocked"],
            window: "all_time",
            exclusions: [],
            cooldown: "once_per_user",
            confidence: "high",
            status: "keep",
            difficulty: "starter",
            expectedFrequency: "once",
            active: true
        )
    }

    private func actuallyWaitContract() -> AchievementContract {
        AchievementContract(
            id: "actually_wait",
            number: 12,
            name: "Actually, Wait",
            category: "prompting_and_context",
            definition: "The user changes direction mid-thread.",
            detectionClass: "keyword",
            signals: ["correction_terms"],
            window: "same_thread_after_first_user_turn",
            exclusions: [],
            cooldown: "once_per_thread",
            confidence: "high",
            status: "keep",
            difficulty: "starter",
            expectedFrequency: "weekly",
            active: true
        )
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
