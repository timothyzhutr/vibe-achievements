import XCTest
@testable import VibeAchievementsCore

final class CursorTranscriptParserTests: XCTestCase {
    func testParsesRoleAndContentItemsInLineOrderAndIgnoresTurnEnded() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("conversation.jsonl")
        try """
        {"role":"user","message":{"content":[{"type":"text","text":"Hello"}]},"timestamp":"2026-07-11T01:00:00.000Z"}
        {"type":"turn_ended"}
        {"role":"assistant","message":{"content":[{"type":"text","text":"Hi"}]},"timestamp":"2026-07-11T01:00:01.000Z"}
        {"role":"tool","message":{"content":[{"type":"text","text":"hidden"}]}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let parsed = try CursorTranscriptParser().parse(
            fileURL: file,
            stableID: "cursor:project:conversation",
            projectPath: "/tmp/cursor-project"
        )

        XCTAssertEqual(parsed.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(parsed.messages.map(\.text), ["Hello", "Hi"])
        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), [nil, nil])
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/cursor-project")
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
