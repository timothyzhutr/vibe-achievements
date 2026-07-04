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

    func testSkipsMalformedJSONAndUnsupportedEntryTypes() throws {
        let parsed = try parseJSONL("""
        {"type":"summary","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":"ignored"}}
        not json
        {"type":"user","timestamp":"2026-07-04T01:01:00.000Z","sessionId":"session-1","message":{"role":"user","content":"kept"}}
        """)

        XCTAssertEqual(parsed.thread.sourceThreadID, "session-1")
        XCTAssertEqual(parsed.thread.messageCount, 1)
        XCTAssertEqual(parsed.messages.map(\.text), ["kept"])
    }

    func testSkipsConflictingLaterSessionIDEntriesAndUsesLockedThreadID() throws {
        let parsed = try parseJSONL("""
        {"type":"user","timestamp":"2026-07-04T01:00:00.000Z","message":{"role":"user","content":"before lock"}}
        {"type":"user","timestamp":"2026-07-04T01:00:05.000Z","sessionId":"session-1","message":{"role":"user","content":"first"}}
        {"type":"assistant","timestamp":"2026-07-04T01:00:10.000Z","sessionId":"session-2","message":{"role":"assistant","content":"wrong thread"}}
        {"type":"assistant","timestamp":"2026-07-04T01:00:20.000Z","message":{"role":"assistant","content":"same thread by omission"}}
        """)

        XCTAssertEqual(parsed.thread.sourceThreadID, "session-1")
        XCTAssertEqual(parsed.messages.map(\.text), ["before lock", "first", "same thread by omission"])
        XCTAssertTrue(parsed.messages.allSatisfy { $0.threadID == parsed.thread.sourceThreadID })
        XCTAssertTrue(parsed.messages.allSatisfy { $0.id.hasPrefix("session-1-") })
    }

    func testArrayTextExtractionIgnoresNonTextContentAndJoinsTextContent() throws {
        let parsed = try parseJSONL("""
        {"type":"assistant","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":[{"type":"tool_result","text":"ignored"},{"type":"text","text":"first"},{"type":"image","source":{"type":"base64"}},{"type":"text","text":"second"}]}}
        """)

        XCTAssertEqual(parsed.messages.single?.text, "first\nsecond")
    }

    func testCreatedAtAndUpdatedAtReflectMinimumAndMaximumTimestamps() throws {
        let parsed = try parseJSONL("""
        {"type":"assistant","timestamp":"2026-07-04T01:02:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":"middle"}}
        {"type":"user","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"user","content":"first"}}
        {"type":"assistant","timestamp":"2026-07-04T01:03:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":"last"}}
        """)

        XCTAssertEqual(parsed.thread.createdAt, date("2026-07-04T01:00:00.000Z"))
        XCTAssertEqual(parsed.thread.updatedAt, date("2026-07-04T01:03:00.000Z"))
    }

    func testRawTokenCountIncludesCacheTokenFields() throws {
        let parsed = try parseJSONL("""
        {"type":"assistant","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":"tokens","usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """)

        XCTAssertEqual(parsed.thread.rawTokenCount, 10)
    }

    func testRawTokenCountIsZeroWhenUsageExistsButAllTokenFieldsAreZero() throws {
        let parsed = try parseJSONL("""
        {"type":"assistant","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"assistant","content":"tokens","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """)

        XCTAssertEqual(parsed.thread.rawTokenCount, 0)
    }

    func testRawTokenCountIsNilWhenNoUsageObjectExists() throws {
        let parsed = try parseJSONL("""
        {"type":"user","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"user","content":"no usage"}}
        """)

        XCTAssertNil(parsed.thread.rawTokenCount)
    }

    func testDoesNotCountToolResultUserRecordsAsHumanTurns() throws {
        let parsed = try parseJSONL("""
        {"type":"user","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"session-1","message":{"role":"user","content":"run the tests"}}
        {"type":"assistant","timestamp":"2026-07-04T01:00:05.000Z","sessionId":"session-1","message":{"role":"assistant","content":[{"type":"text","text":"Running them."}]}}
        {"type":"user","timestamp":"2026-07-04T01:00:10.000Z","sessionId":"session-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"3 passed"}]}}
        {"type":"user","timestamp":"2026-07-04T01:00:20.000Z","sessionId":"session-1","message":{"role":"user","content":"nice, ship it"}}
        """)

        // Two real human prompts, not three — the tool_result row is excluded.
        XCTAssertEqual(parsed.thread.userTurnCount, 2)
        XCTAssertEqual(parsed.thread.messageCount, 3)
        XCTAssertFalse(parsed.messages.contains { $0.text.isEmpty })
    }

    private func parseJSONL(_ contents: String) throws -> ParsedTranscript {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("transcript.jsonl")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try ClaudeCodeParser.parse(fileURL: fileURL)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
