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
}
