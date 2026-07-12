import XCTest
@testable import VibeAchievementsApp
import VibeAchievementsCore

final class AppStateTests: XCTestCase {
    @MainActor
    func testStartupLoadsCachedAchievementsBeforeRescanCompletes() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = try SQLiteStore(path: path)
        try store.insert(unlock: AchievementUnlock(
            achievementID: "actually_wait",
            name: "Actually, Wait",
            projectKey: "/tmp/project",
            threadID: "codex:thread",
            unlockedAt: Date(timeIntervalSince1970: 1_000),
            triggerSummary: "Changed direction."
        ))

        let state = AppState(storePath: path, sourceSettingsDefaults: defaults)

        XCTAssertFalse(state.achievementContracts.isEmpty)
        XCTAssertEqual(state.recentUnlocks.map(\.achievementID), ["actually_wait"])
        XCTAssertEqual(state.sourceSummary, "Refreshing sources")
        XCTAssertEqual(state.lastScanSummary, "Loaded 1 cached achievement")
    }

    func testFingerprintIncludesDetectorVersion() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(SourceFileFingerprint.make(for: url, detectorVersion: AppState.detectorFingerprintVersion).hasPrefix(AppState.detectorFingerprintVersion + "-"))
    }

    func testSourceSummaryIncludesEverySourceStatus() {
        let statuses = [
            ConversationSourceStatus(sourceTool: .claudeCode, displayName: "Claude Code", state: .connected, recordCount: 3, warningCount: 0),
            ConversationSourceStatus(sourceTool: .codex, displayName: "Codex", state: .unavailable, recordCount: 0, warningCount: 0)
        ]

        let summary = AppState.sourceSummary(for: statuses)

        XCTAssertTrue(summary.contains("Claude Code: 3 conversations"))
        XCTAssertTrue(summary.contains("Codex: unavailable"))
    }

    @MainActor
    func testPublishesLatestStatusBySourceTool() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = AppState(
            storePath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite",
            sourceSettingsDefaults: defaults
        )
        let claudeStatus = ConversationSourceStatus(
            sourceTool: .claudeCode,
            displayName: "Claude Code",
            state: .connected,
            recordCount: 3,
            warningCount: 0
        )
        let cursorStatus = ConversationSourceStatus(
            sourceTool: .cursor,
            displayName: "Cursor",
            state: .needsAttention,
            recordCount: 1,
            warningCount: 2
        )

        state.applySourceStatuses([claudeStatus, cursorStatus])

        XCTAssertEqual(state.sourceStatuses, [
            .claudeCode: claudeStatus,
            .cursor: cursorStatus
        ])
    }

    @MainActor
    func testDoesNotPublishStatusesFromScanSupersededBySourceSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = AppState(
            storePath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite",
            sourceSettingsDefaults: defaults
        )
        let staleStatus = ConversationSourceStatus(
            sourceTool: .claudeCode,
            displayName: "Claude Code",
            state: .connected,
            recordCount: 3,
            warningCount: 0
        )

        state.scanNow()
        let supersededRevision = state.sourceConfigurationRevision
        state.updateSourceSettings { $0.cursorEnabled.toggle() }
        state.applySourceStatuses([staleStatus], fromSourceConfigurationRevision: supersededRevision)

        XCTAssertTrue(state.sourceStatuses.isEmpty)
    }

    @MainActor
    func testRepeatedOrdinaryScanRequestsDoNotInvalidateCurrentResult() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = AppState(
            storePath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite",
            sourceSettingsDefaults: defaults
        )
        let currentStatus = ConversationSourceStatus(
            sourceTool: .claudeCode,
            displayName: "Claude Code",
            state: .connected,
            recordCount: 3,
            warningCount: 0
        )

        state.scanNow()
        let activeRevision = state.sourceConfigurationRevision
        state.scanNow()
        state.applySourceStatuses([currentStatus], fromSourceConfigurationRevision: activeRevision)

        XCTAssertEqual(state.sourceStatuses[.claudeCode], currentStatus)
    }

    func testNotificationStateIsMarkedOnlyWhenNotificationsCanSchedule() {
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: false, notificationsAvailable: true, pendingCount: 1))
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: false, pendingCount: 1))
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: true, pendingCount: 0))
        XCTAssertTrue(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: true, pendingCount: 1))
    }
}
