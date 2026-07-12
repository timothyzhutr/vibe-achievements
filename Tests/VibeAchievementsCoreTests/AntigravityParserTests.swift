import Foundation
import XCTest
@testable import VibeAchievementsCore

final class AntigravityParserTests: XCTestCase {
    func testParsesVisibleTrajectoryVariantsInLineOrderAndIgnoresTools() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "antigravity-trajectory", withExtension: "jsonl"))
        let data = try Data(contentsOf: fixture)
            + Data(#"{"type":"user_input","text":"partial"#.utf8)

        let result = try AntigravityParser.parse(
            data: data,
            sourceTool: .codex,
            threadID: "antigravity:ide:fixture",
            sourcePath: fixture.path
        )

        XCTAssertEqual(result.transcript.thread.sourceThreadID, "antigravity:ide:fixture")
        XCTAssertEqual(result.transcript.thread.sourceTool, .codex)
        XCTAssertEqual(result.transcript.thread.projectPath, "/tmp/vibe-app")
        XCTAssertEqual(result.transcript.messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(result.transcript.messages.map(\.text), [
            "Build the small feature",
            "I will inspect the existing shape first.",
            "The feature is ready."
        ])
        XCTAssertEqual(result.transcript.thread.messageCount, 3)
        XCTAssertEqual(result.transcript.thread.userTurnCount, 1)
        XCTAssertEqual(result.transcript.thread.assistantTurnCount, 2)
        XCTAssertEqual(result.warnings.map(\.kind), [.unknownVariant])
    }

    func testToleratesAlternateNestedMessageShapesAndPreservesMissingTimestamp() throws {
        let data = [
            #"{"kind":"user","message":{"text":"hello"},"workspacePath":"/tmp/alternate"}"#,
            #"{"event":"planner","response":{"content":[{"type":"text","text":"plan"}]}}"#,
            #"{"type":"ephemeral","text":"ignore me"}"#,
            #"{"type":"tool_result","output":"ignore me too"}"#,
            #"{"role":"assistant","content":"done"}"#
        ].joined(separator: "\n").data(using: .utf8)!

        let result = try AntigravityParser.parse(
            data: data,
            sourceTool: .codex,
            threadID: "trajectory",
            sourcePath: "/tmp/trajectory.jsonl"
        )

        XCTAssertEqual(result.transcript.messages.map(\.text), ["hello", "plan", "done"])
        XCTAssertEqual(result.transcript.messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertNil(result.transcript.messages[0].timestamp)
        XCTAssertEqual(result.transcript.thread.projectPath, "/tmp/alternate")
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testUsesCurrentDirectoryWhenWorkspacePathIsNotPresent() throws {
        let data = [
            #"{"type":"user_input","currentDirectory":"/tmp/current","text":"hello"}"#,
            #"{"type":"planner_response","timestamp":1720656000,"text":"hi"}"#
        ].joined(separator: "\n").data(using: .utf8)!

        let result = try AntigravityParser.parse(
            data: data,
            sourceTool: .codex,
            threadID: "trajectory",
            sourcePath: "/tmp/trajectory.jsonl"
        )

        XCTAssertEqual(result.transcript.thread.projectPath, "/tmp/current")
        XCTAssertEqual(result.transcript.messages[1].timestamp, Date(timeIntervalSince1970: 1720656000))
    }

    func testDigestUsesRoleAndTextOrderAndKeepsPrefixForksDifferent() throws {
        let first = [
            #"{"type":"user_input","text":"same"}"#,
            #"{"type":"planner_response","text":"answer"}"#
        ].joined(separator: "\n").data(using: .utf8)!
        let second = first + #"{"type":"user_input","text":"extra"}"#.data(using: .utf8)!

        let firstResult = try AntigravityParser.parse(
            data: first,
            sourceTool: .codex,
            threadID: "first",
            sourcePath: "/tmp/first.jsonl"
        )
        let secondResult = try AntigravityParser.parse(
            data: second,
            sourceTool: .codex,
            threadID: "second",
            sourcePath: "/tmp/second.jsonl"
        )

        XCTAssertEqual(
            AntigravityParser.normalizedDigest(for: firstResult.transcript),
            AntigravityParser.normalizedDigest(for: firstResult.transcript)
        )
        XCTAssertNotEqual(
            AntigravityParser.normalizedDigest(for: firstResult.transcript),
            AntigravityParser.normalizedDigest(for: secondResult.transcript)
        )
    }
}
