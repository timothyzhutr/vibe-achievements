import XCTest
@testable import VibeAchievementsCore

final class ConversationSourceRegistryTests: XCTestCase {
    func testRegistryOrderIncludesAllSupportedSources() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude/projects"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/sessions"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support/Cursor"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".cursor/projects"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".local/share/opencode"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".gemini/antigravity/brain"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".gemini/antigravity-cli/brain"),
            withIntermediateDirectories: true
        )

        let registrations = ConversationSourceRegistry.registrations(
            home: home,
            configuration: SourceConfiguration(),
            environment: [:],
            detectorVersion: "test"
        )

        XCTAssertEqual(registrations.map(\.sourceTool), [.claudeCode, .codex, .cursor, .openCode, .antigravity])
        XCTAssertTrue(registrations.allSatisfy { $0.adapter != nil })
    }

    func testSourceStatesHaveDistinctSummaries() {
        let statuses = [
            ConversationSourceStatus(sourceTool: .claudeCode, displayName: "Connected", state: .connected, recordCount: 2, warningCount: 0),
            ConversationSourceStatus(sourceTool: .claudeCode, displayName: "Empty", state: .empty, recordCount: 0, warningCount: 0),
            ConversationSourceStatus(sourceTool: .claudeCode, displayName: "Unavailable", state: .unavailable, recordCount: 0, warningCount: 0),
            ConversationSourceStatus(sourceTool: .claudeCode, displayName: "Attention", state: .needsAttention, recordCount: 1, warningCount: 1)
        ]

        XCTAssertEqual(Set(statuses.map(\.summary)).count, 4)
        XCTAssertTrue(statuses[0].summary.contains("2 conversations"))
        XCTAssertTrue(statuses[1].summary.contains("no conversations"))
        XCTAssertTrue(statuses[2].summary.contains("unavailable"))
        XCTAssertTrue(statuses[3].summary.contains("needs attention"))
    }
}
