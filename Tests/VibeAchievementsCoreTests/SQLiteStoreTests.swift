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

    func testReadsStoredUnlocksNewestFirst() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        try store.insert(unlock: AchievementUnlock(
            achievementID: "actually_wait",
            name: "Actually, Wait",
            projectKey: "/tmp/a",
            threadID: "thread-a",
            unlockedAt: older,
            triggerSummary: "Changed direction."
        ))
        try store.insert(unlock: AchievementUnlock(
            achievementID: "rm_rf",
            name: "rm -rf",
            projectKey: "/tmp/b",
            threadID: "thread-b",
            unlockedAt: newer,
            triggerSummary: "Recovered after cleanup."
        ))

        let unlocks = try store.allUnlocks()

        XCTAssertEqual(unlocks.map(\.achievementID), ["rm_rf", "actually_wait"])
        XCTAssertEqual(unlocks.first?.projectKey, "/tmp/b")
        XCTAssertEqual(unlocks.first?.threadID, "thread-b")
    }
}
