import XCTest
@testable import VibeAchievementsApp
import VibeAchievementsCore

final class AppStateTests: XCTestCase {
    func testWarningsDoNotSuppressNotificationsButHardErrorsDo() {
        // Soft warnings surface via `error`, not `hardError`, so they must not
        // block notifications; a hard failure or sendNotifications:false does.
        XCTAssertTrue(AppState.notificationsAllowed(sendNotifications: true, hardError: nil))
        XCTAssertFalse(AppState.notificationsAllowed(sendNotifications: true, hardError: "Scan failed"))
        XCTAssertFalse(AppState.notificationsAllowed(sendNotifications: false, hardError: nil))
    }

    func testBackfillSummaryIsMarkedDeliveredOnlyWhenThereAreUnlocks() {
        XCTAssertFalse(AppState.shouldMarkBackfillSummaryDelivered(totalUnlocks: 0))
        XCTAssertTrue(AppState.shouldMarkBackfillSummaryDelivered(totalUnlocks: 1))
    }

    func testPendingScanRequestsKeepQuietRescansAndUpgradeToNotifying() {
        XCTAssertEqual(AppState.mergedPendingScanSendsNotifications(existing: nil, incoming: false), false)
        XCTAssertEqual(AppState.mergedPendingScanSendsNotifications(existing: false, incoming: false), false)
        XCTAssertEqual(AppState.mergedPendingScanSendsNotifications(existing: false, incoming: true), true)
        XCTAssertEqual(AppState.mergedPendingScanSendsNotifications(existing: true, incoming: false), true)
    }

    func testFailedParseFilesAreNotFingerprintRecorded() {
        let warnings = [IndexWarning(path: "/tmp/bad.jsonl", message: "bad json")]

        XCTAssertFalse(AppState.shouldRecordFingerprint(for: "/tmp/bad.jsonl", warnings: warnings))
        XCTAssertTrue(AppState.shouldRecordFingerprint(for: "/tmp/good.jsonl", warnings: warnings))
    }

    func testFingerprintIncludesDetectorVersion() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".jsonl")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(AppState.fingerprint(for: url).hasPrefix(AppState.detectorFingerprintVersion + "-"))
    }
}
