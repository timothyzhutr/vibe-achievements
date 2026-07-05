import XCTest
@testable import VibeAchievementsCore

final class AchievementEngineTests: XCTestCase {
    private let bucketAContractIDs: Set<String> = [
        "actually_wait",
        "one_more_prompt",
        "prompt_it_into_existence",
        "weekend_mvp_energy",
        "the_message_had_mass",
        "confidence_high_context_low",
        "context_window_sunset",
        "token_budget_lifestyle",
        "the_app_has_opinions",
        "lore_drop",
        "stack_trace_oracle",
        "one_more_run",
        "green_bar_acquired",
        "green_by_coincidence",
        "understanding_optional",
        "we_are_so_back",
        "rubber_duck_with_a_gpu",
        "it_works_therefore_it_is",
        "nobody_touch_it",
        "production_is_a_place",
        "the_button_exists_now",
        "css_negotiations",
        "cache_clearing_ritual",
        "rm_rf",
        "lgtm_from_the_void",
        "shipwright"
    ]

    func testBucketAContractsAllHaveRules() throws {
        let contracts = try AchievementContractLoader.loadBundledV1()
        let activeContractIDs = Set(contracts.filter { $0.active && $0.status == "keep" }.map(\.id))

        XCTAssertTrue(bucketAContractIDs.isSubset(of: activeContractIDs))
        XCTAssertEqual(Set(AchievementEngine.ruleIDs), bucketAContractIDs)
    }

    func testEventSummaryCountsPresenceAndOrderedSequences() {
        let base = Date(timeIntervalSince1970: 1_000)
        let events = [
            event(.successSeen, timestamp: base.addingTimeInterval(3)),
            event(.implementationOrFixSeen, timestamp: base.addingTimeInterval(1)),
            event(.implementationOrFixSeen, timestamp: base.addingTimeInterval(2))
        ]

        let summary = EventSummary(events: events)

        XCTAssertTrue(summary.has(.successSeen))
        XCTAssertEqual(summary.count(.implementationOrFixSeen), 2)
        XCTAssertTrue(summary.sequence([.implementationOrFixSeen, .successSeen]))
        XCTAssertFalse(summary.sequence([.successSeen, .implementationOrFixSeen]))
    }

    func testBucketAPresenceAndCooccurrenceAchievementsUnlock() throws {
        let cases: [(String, ParsedTranscript)] = [
            ("prompt_it_into_existence", transcript(userTexts: ["build me a small menu bar app"])),
            ("weekend_mvp_energy", transcript(userTexts: ["this is a weekend project prototype"])),
            ("the_message_had_mass", transcript(userTexts: [String(repeating: "context ", count: 300)])),
            ("context_window_sunset", transcript(userTexts: ["we are running out of context window here"])),
            ("token_budget_lifestyle", transcript(userTexts: ["we need to watch the token budget and cost"])),
            ("stack_trace_oracle", transcript(userTexts: ["Traceback: fatal Error: exit code 1"])),
            ("green_by_coincidence", transcript(userTexts: ["somehow it works now, no idea why"])),
            ("understanding_optional", transcript(userTexts: ["I don't know why this works"])),
            ("lgtm_from_the_void", transcript(userTexts: ["LGTM, approved, good to merge"])),
            ("the_button_exists_now", transcript(userTexts: ["add a settings panel with a toggle and button"])),
            ("cache_clearing_ritual", transcript(userTexts: ["clear cache and restart server"])),
            ("shipwright", transcript(userTexts: ["commit this and open a pull request"])),
            ("nobody_touch_it", transcript(userTexts: ["it works now", "don't touch it"])),
            ("production_is_a_place", transcript(userTexts: ["this MVP prototype can go live for real users"]))
        ]

        try assertUnlockCases(cases)
    }

    func testBucketACountAchievementsUnlockAtThreshold() throws {
        let cases: [(String, ParsedTranscript)] = [
            ("one_more_run", transcript(userTexts: ["fix it", "run again", "still failing", "retry once more"])),
            ("css_negotiations", transcript(userTexts: ["the UI layout needs CSS", "adjust margin padding and spacing"]))
        ]

        try assertUnlockCases(cases)

        XCTAssertFalse(try unlockIDs(for: transcript(userTexts: ["fix it", "run it", "still failing"])).contains("one_more_run"))
        XCTAssertFalse(try unlockIDs(for: transcript(userTexts: ["the UI component needs tweaks", "adjust margin and padding"])).contains("css_negotiations"))
    }

    func testBucketASequenceAchievementsUnlockOnlyInOrder() throws {
        let cases: [(String, ParsedTranscript)] = [
            ("the_app_has_opinions", transcript(entries: [(.assistant, "I would avoid that. A safer approach is smaller."), (.user, "okay continue")])),
            ("lore_drop", transcript(userTexts: [String(repeating: "for context, here is the background. ", count: 70) + "please implement it"])),
            ("green_bar_acquired", transcript(userTexts: ["the test suite is failing red", "now all tests pass and green"])),
            ("we_are_so_back", transcript(userTexts: ["the app is broken and stuck", "it works now"])),
            ("confidence_high_context_low", transcript(userTexts: ["one", "two", "three", "four", "five", "six", "seven", "the context window is almost gone", "continue anyway"])),
            ("rubber_duck_with_a_gpu", transcript(userTexts: ["let me think through the tradeoff", "therefore the conclusion makes sense"]))
        ]

        try assertUnlockCases(cases)

        XCTAssertFalse(try unlockIDs(for: transcript(userTexts: ["now all tests pass", "the test suite is failing"])).contains("green_bar_acquired"))
        XCTAssertFalse(try unlockIDs(for: transcript(userTexts: ["it works now", "the app is broken"])).contains("we_are_so_back"))
        XCTAssertFalse(try unlockIDs(for: transcript(userTexts: ["let me think through the tradeoff", "please implement the fix", "therefore the conclusion makes sense"])).contains("rubber_duck_with_a_gpu"))
    }

    func testUnlocksActuallyWaitAndRmRf() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)

        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let claude = try ClaudeCodeParser.parse(fileURL: claudeURL)
        let claudeUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: claude, events: EventExtractor.extract(from: claude), existingUnlockedIDs: ["achievement_unlocked_unlocking_achievement"])

        let codexURL = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let codex = try CodexParser.parse(fileURL: codexURL)
        let codexUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: codex, events: EventExtractor.extract(from: codex), existingUnlockedIDs: ["achievement_unlocked_unlocking_achievement"])

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
            existingUnlockedIDs: Set(firstPass.map(\.achievementID))
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
            existingUnlockedIDs: Set(unlocksA.map(\.achievementID))
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
            existingUnlockedIDs: Set(unlocksA.map(\.achievementID))
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

    private func assertUnlockCases(_ cases: [(String, ParsedTranscript)]) throws {
        for (id, parsed) in cases {
            let ids = try unlockIDs(for: parsed)
            XCTAssertTrue(ids.contains(id), "\(id) should unlock for transcript")
        }
    }

    private func unlockIDs(for parsed: ParsedTranscript) throws -> Set<String> {
        let contracts = try AchievementContractLoader.loadBundledV1()
        return Set(AchievementEngine
            .evaluate(
                contracts: contracts,
                parsed: parsed,
                events: EventExtractor.extract(from: parsed),
                existingUnlockedIDs: ["achievement_unlocked_unlocking_achievement"]
            )
            .map(\.achievementID))
    }

    private func event(_ type: EventType, timestamp: Date?) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: .claudeCode, projectKey: "/tmp/p", threadID: "claude_code:t", messageID: nil, timestamp: timestamp, confidence: "high")
    }

    private func transcript(userTexts: [String]) -> ParsedTranscript {
        transcript(entries: userTexts.map { (.user, $0) })
    }

    private func transcript(entries: [(MessageRole, String)]) -> ParsedTranscript {
        let base = Date(timeIntervalSince1970: 1_000)
        let messages = entries.enumerated().map { index, entry in
            NormalizedMessage(id: "m\(index)", threadID: "claude_code:t", sourceTool: .claudeCode, sourceMessageID: nil, role: entry.0, timestamp: base.addingTimeInterval(Double(index)), text: entry.1, rawType: entry.0.rawValue)
        }
        let userTurns = entries.filter { $0.0 == .user }.count
        let assistantTurns = entries.filter { $0.0 == .assistant }.count
        let thread = NormalizedThread(id: "claude_code:t", sourceTool: .claudeCode, sourceThreadID: "t", sourcePath: "/tmp/t.jsonl", projectPath: "/tmp/p", projectKey: "/tmp/p", title: nil, createdAt: base, updatedAt: base.addingTimeInterval(Double(messages.count)), messageCount: messages.count, userTurnCount: userTurns, assistantTurnCount: assistantTurns, estimatedTokens: 1, rawTokenCount: nil)
        return ParsedTranscript(thread: thread, messages: messages)
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
