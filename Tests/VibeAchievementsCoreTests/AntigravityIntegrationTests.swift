import XCTest
@testable import VibeAchievementsCore

final class AntigravityIntegrationTests: XCTestCase {
    func testAntigravityRecordsIndexOnceAndUnchangedRescanDoesNotReparse() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityIntegration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ideBrain = root.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        let cliBrain = root.appendingPathComponent(".gemini/antigravity-cli/brain", isDirectory: true)
        try FileManager.default.createDirectory(at: ideBrain, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cliBrain, withIntermediateDirectories: true)
        let conversation = ideBrain
            .appendingPathComponent("11111111-1111-1111-1111-111111111111/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: conversation, withIntermediateDirectories: true)
        try "{\"type\":\"user_input\",\"text\":\"hello\"}\n{\"type\":\"planner_response\",\"text\":\"world\"}\n"
            .write(to: conversation.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let adapter = AntigravitySourceAdapter(home: root, detectorVersion: "test")
        let store = try SQLiteStore(path: root.appendingPathComponent("app.sqlite").path)

        let first = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        let second = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")

        XCTAssertEqual(first.changedRecordCount, 1)
        XCTAssertEqual(second.changedRecordCount, 0)
        XCTAssertTrue(first.warnings.isEmpty)
        XCTAssertEqual(first.sourceStatuses.first?.state, .connected)
    }
}
