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

    func testMessagesBeforeLateSessionMetaGetFinalThreadID() throws {
        let lines = [
            #"{"type":"response_item","timestamp":"2026-07-04T02:00:00.000Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}"#,
            #"{"type":"session_meta","timestamp":"2026-07-04T02:00:01.000Z","payload":{"id":"real-session","cwd":"/tmp/p"}}"#,
            #"{"type":"response_item","timestamp":"2026-07-04T02:00:02.000Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi"}]}}"#
        ].joined(separator: "\n")
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")
        try lines.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try CodexParser.parse(fileURL: url)

        XCTAssertEqual(parsed.thread.sourceThreadID, "real-session")
        XCTAssertTrue(parsed.messages.allSatisfy { $0.threadID == "real-session" })
        XCTAssertTrue(parsed.messages.allSatisfy { $0.id.hasPrefix("real-session-") })
    }

    func testCumulativeTokenTotalsAreNotSummed() throws {
        // total_token_usage is cumulative per session; two events reporting 100
        // then 250 must yield 250, not 350.
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-07-04T02:00:00.000Z","payload":{"id":"s","cwd":"/tmp/p"}}"#,
            #"{"type":"event_msg","timestamp":"2026-07-04T02:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"output_tokens":20}}}}"#,
            #"{"type":"event_msg","timestamp":"2026-07-04T02:00:02.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"output_tokens":50}}}}"#
        ].joined(separator: "\n")
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")
        try lines.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try CodexParser.parse(fileURL: url)
        XCTAssertEqual(parsed.thread.rawTokenCount, 250)
    }
}
