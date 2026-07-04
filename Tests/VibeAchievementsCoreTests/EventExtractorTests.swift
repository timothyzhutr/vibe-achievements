import XCTest
@testable import VibeAchievementsCore

final class EventExtractorTests: XCTestCase {
    func testExtractsCorrectionAndCleanupEvents() throws {
        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let codexURL = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))

        let claudeEvents = EventExtractor.extract(from: try ClaudeCodeParser.parse(fileURL: claudeURL))
        let codexEvents = EventExtractor.extract(from: try CodexParser.parse(fileURL: codexURL))

        XCTAssertTrue(claudeEvents.contains { $0.type == .correctionLanguageSeen })
        XCTAssertTrue(codexEvents.contains { $0.type == .destructiveCleanupSeen })
        XCTAssertTrue(codexEvents.contains { $0.type == .recoverySeen || $0.type == .successSeen })
    }

    func testCorrectionInFirstUserTurnIsIgnored() {
        // A thread that opens with "wait/actually" has no prior direction to
        // change, so it must not count as a mid-thread course-correction.
        let parsed = makeUserTranscript(["wait, actually build the menu bar app instead"])
        let events = EventExtractor.extract(from: parsed)
        XCTAssertFalse(events.contains { $0.type == .correctionLanguageSeen })
    }

    func testCorrectionAfterFirstUserTurnIsFlagged() {
        let parsed = makeUserTranscript(["build me an app", "actually, wait, make it a CLI instead"])
        let events = EventExtractor.extract(from: parsed)
        XCTAssertTrue(events.contains { $0.type == .correctionLanguageSeen })
    }

    private func makeUserTranscript(_ texts: [String]) -> ParsedTranscript {
        let messages = texts.enumerated().map { index, text in
            NormalizedMessage(id: "m\(index)", threadID: "claude_code:t", sourceTool: .claudeCode, sourceMessageID: nil, role: .user, timestamp: nil, text: text, rawType: "user")
        }
        let thread = NormalizedThread(id: "claude_code:t", sourceTool: .claudeCode, sourceThreadID: "t", sourcePath: "/tmp/t.jsonl", projectPath: "/tmp/p", projectKey: "/tmp/p", title: nil, createdAt: nil, updatedAt: nil, messageCount: messages.count, userTurnCount: messages.count, assistantTurnCount: 0, estimatedTokens: 1, rawTokenCount: nil)
        return ParsedTranscript(thread: thread, messages: messages)
    }
}
