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

    func testEqualTimestampsOrderDeterministicallyByInsertion() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        let sameInstant = Date(timeIntervalSince1970: 1_000)

        try store.insert(unlock: AchievementUnlock(
            achievementID: "first_inserted",
            name: "First",
            projectKey: "/tmp/a",
            threadID: "thread-a",
            unlockedAt: sameInstant,
            triggerSummary: "First."
        ))
        try store.insert(unlock: AchievementUnlock(
            achievementID: "second_inserted",
            name: "Second",
            projectKey: "/tmp/b",
            threadID: "thread-b",
            unlockedAt: sameInstant,
            triggerSummary: "Second."
        ))

        // Identical timestamps must not produce arbitrary ordering: the most
        // recently inserted row wins the tiebreak, stably across queries.
        XCTAssertEqual(try store.allUnlocks().map(\.achievementID), ["second_inserted", "first_inserted"])
        XCTAssertEqual(try store.allUnlocks().map(\.achievementID), ["second_inserted", "first_inserted"])
    }

    func testSameAchievementIsStoredOnceEvenWithDifferentScopes() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)

        try store.insert(unlock: AchievementUnlock(
            achievementID: "actually_wait",
            name: "Actually, Wait",
            projectKey: "/tmp/a",
            threadID: "thread-a",
            unlockedAt: Date(timeIntervalSince1970: 100),
            triggerSummary: "Changed direction."
        ))
        try store.insert(unlock: AchievementUnlock(
            achievementID: "actually_wait",
            name: "Actually, Wait",
            projectKey: "/tmp/b",
            threadID: "thread-b",
            unlockedAt: Date(timeIntervalSince1970: 200),
            triggerSummary: "Changed direction again."
        ))

        XCTAssertEqual(try store.unlockCount(), 1)
        XCTAssertEqual(try store.allUnlocks().map(\.achievementID), ["actually_wait"])
        XCTAssertTrue(try store.unlockedAchievementIDs().contains("actually_wait"))
    }

    func testUnnotifiedUnlocksTrackPerAchievementNotificationState() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)

        try store.insert(unlock: AchievementUnlock(achievementID: "a", name: "A", projectKey: nil, threadID: nil, unlockedAt: Date(timeIntervalSince1970: 100), triggerSummary: "first"))
        try store.insert(unlock: AchievementUnlock(achievementID: "b", name: "B", projectKey: nil, threadID: nil, unlockedAt: Date(timeIntervalSince1970: 200), triggerSummary: "second"))

        // Everything starts unnotified, oldest first.
        XCTAssertEqual(try store.unnotifiedUnlocks().map(\.achievementID), ["a", "b"])

        try store.markNotified(["a"])
        XCTAssertEqual(try store.unnotifiedUnlocks().map(\.achievementID), ["b"])

        try store.markNotified(["b"])
        XCTAssertTrue(try store.unnotifiedUnlocks().isEmpty)
    }

    func testNotificationStateSurvivesReopen() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        try store.insert(unlock: AchievementUnlock(achievementID: "a", name: "A", projectKey: nil, threadID: nil, unlockedAt: Date(timeIntervalSince1970: 100), triggerSummary: "x"))
        try store.markNotified(["a"])

        // A new unlock recorded later is still pending; the old one stays notified.
        let reopened = try SQLiteStore(path: path)
        try reopened.insert(unlock: AchievementUnlock(achievementID: "b", name: "B", projectKey: nil, threadID: nil, unlockedAt: Date(timeIntervalSince1970: 200), triggerSummary: "y"))
        XCTAssertEqual(try reopened.unnotifiedUnlocks().map(\.achievementID), ["b"])
    }

    func testFileFingerprintsPersistAndUpdate() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)

        XCTAssertTrue(try store.knownFileFingerprints().isEmpty)

        try store.recordFileFingerprint(path: "/tmp/a.jsonl", fingerprint: "fp-1")
        XCTAssertEqual(try store.knownFileFingerprints(), ["/tmp/a.jsonl": "fp-1"])

        // Re-recording the same path overwrites rather than duplicating.
        try store.recordFileFingerprint(path: "/tmp/a.jsonl", fingerprint: "fp-2")
        XCTAssertEqual(try store.knownFileFingerprints(), ["/tmp/a.jsonl": "fp-2"])

        // Fingerprints survive reopening the same database file.
        let reopened = try SQLiteStore(path: path)
        XCTAssertEqual(try reopened.knownFileFingerprints(), ["/tmp/a.jsonl": "fp-2"])
    }

    func testSourceRecordStatePersistsAndUpdatesByTypedIdentity() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        let identity = SourceRecordIdentity(sourceTool: .claudeCode, stableID: "session")

        XCTAssertNil(try store.sourceRecord(identity: identity))
        try store.recordSourceRecord(
            record: ConversationSourceRecord(
                sourceTool: .claudeCode,
                stableID: "session",
                displayPath: "/tmp/session.jsonl",
                locator: .file(URL(fileURLWithPath: "/tmp/session.jsonl")),
                fingerprint: "fp-1"
            ),
            threadID: "claude_code:session",
            scanID: "scan-1"
        )

        let reopened = try SQLiteStore(path: path)
        let state = try XCTUnwrap(reopened.sourceRecord(identity: identity))
        XCTAssertEqual(state.fingerprint, "fp-1")
        XCTAssertEqual(state.threadID, "claude_code:session")
        XCTAssertEqual(state.lastSeenScanID, "scan-1")
        XCTAssertEqual(state.missingScanCount, 0)
    }

    func testReconciliationKeepsThreadReferencedByAnotherSourceRecord() throws {
        let store = try SQLiteStore(path: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        let thread = NormalizedThread(
            id: "claude_code:shared",
            sourceTool: .claudeCode,
            sourceThreadID: "shared",
            sourcePath: "/tmp/shared.jsonl",
            projectPath: nil,
            projectKey: "unknown-project",
            title: nil,
            createdAt: nil,
            updatedAt: nil,
            messageCount: 0,
            userTurnCount: 0,
            assistantTurnCount: 0,
            estimatedTokens: 0,
            rawTokenCount: nil
        )
        try store.upsert(thread: thread)
        for id in ["old-name", "new-name"] {
            try store.recordSourceRecord(
                record: ConversationSourceRecord(
                    sourceTool: .claudeCode,
                    stableID: id,
                    displayPath: "/tmp/\(id).jsonl",
                    locator: .file(URL(fileURLWithPath: "/tmp/\(id).jsonl")),
                    fingerprint: "fp"
                ),
                threadID: thread.id,
                scanID: "scan-1"
            )
        }

        try store.reconcileMissingSourceRecords(sourceTool: .claudeCode, seenRecordIDs: ["new-name"], scanID: "scan-2")
        try store.reconcileMissingSourceRecords(sourceTool: .claudeCode, seenRecordIDs: ["new-name"], scanID: "scan-3")

        XCTAssertTrue(try store.threadExists(id: thread.id))
        XCTAssertNil(try store.sourceRecord(identity: SourceRecordIdentity(sourceTool: .claudeCode, stableID: "old-name")))
        XCTAssertNotNil(try store.sourceRecord(identity: SourceRecordIdentity(sourceTool: .claudeCode, stableID: "new-name")))
    }

    func testMigratedLegacyRecordDoesNotReappearAfterReconciliationAndReopen() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        try store.recordFileFingerprint(
            path: "/tmp/.claude/projects/project/retired.jsonl",
            fingerprint: "legacy-fp"
        )
        let migrated = try SQLiteStore(path: path)
        let identity = SourceRecordIdentity(sourceTool: .claudeCode, stableID: "retired")
        XCTAssertNotNil(try migrated.sourceRecord(identity: identity))

        try migrated.reconcileMissingSourceRecords(sourceTool: .claudeCode, seenRecordIDs: [], scanID: "scan-1")
        try migrated.reconcileMissingSourceRecords(sourceTool: .claudeCode, seenRecordIDs: [], scanID: "scan-2")
        XCTAssertNil(try migrated.sourceRecord(identity: identity))

        let reopened = try SQLiteStore(path: path)
        XCTAssertNil(try reopened.sourceRecord(identity: identity))
    }
}
