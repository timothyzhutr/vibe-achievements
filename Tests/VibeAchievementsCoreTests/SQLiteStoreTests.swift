import XCTest
@testable import VibeAchievementsCore

final class SQLiteStoreTests: XCTestCase {
    func testStoresThreadAndUnlock() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let parsed = try CodexParser.parse(fileURL: url)

        try store.upsert(thread: parsed.thread)
        try store.insert(unlock: AchievementUnlock(
            achievementID: "rm_rf",
            name: "rm -rf",
            projectKey: parsed.thread.projectKey,
            threadID: parsed.thread.id,
            unlockedAt: Date(),
            triggerSummary: "Destructive cleanup was followed by recovery."
        ))

        XCTAssertEqual(try store.unlockCount(), 1)
    }
}
