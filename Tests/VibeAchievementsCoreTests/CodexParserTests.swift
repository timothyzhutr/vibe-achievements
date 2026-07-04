import XCTest
@testable import VibeAchievementsCore

final class CodexParserTests: XCTestCase {
    func testParsesCodexTranscript() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let parsed = try CodexParser.parse(fileURL: url)

        XCTAssertEqual(parsed.thread.sourceTool, .codex)
        XCTAssertEqual(parsed.thread.sourceThreadID, "codex-session-1")
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/vibe-app")
        XCTAssertEqual(parsed.thread.messageCount, 3)
        XCTAssertEqual(parsed.thread.userTurnCount, 2)
        XCTAssertEqual(parsed.thread.assistantTurnCount, 1)
        XCTAssertEqual(parsed.thread.rawTokenCount, 150)
        XCTAssertTrue(parsed.messages.map(\.text).joined(separator: "\n").contains("rm -rf"))
    }
}
