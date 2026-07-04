import XCTest
@testable import VibeAchievementsCore

final class ClaudeCodeParserTests: XCTestCase {
    func testParsesClaudeCodeTranscript() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let parsed = try ClaudeCodeParser.parse(fileURL: url)

        XCTAssertEqual(parsed.thread.sourceTool, .claudeCode)
        XCTAssertEqual(parsed.thread.sourceThreadID, "claude-session-1")
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/vibe-app")
        XCTAssertEqual(parsed.thread.messageCount, 3)
        XCTAssertEqual(parsed.thread.userTurnCount, 2)
        XCTAssertEqual(parsed.thread.assistantTurnCount, 1)
        XCTAssertEqual(parsed.thread.rawTokenCount, 140)
        XCTAssertTrue(parsed.messages.map(\.text).joined(separator: "\n").contains("Actually, wait"))
    }
}
