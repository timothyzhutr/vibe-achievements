import XCTest
@testable import VibeAchievementsApp
import VibeAchievementsCore

final class AppStateTests: XCTestCase {
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

    func testNotificationStateIsMarkedOnlyWhenNotificationsCanSchedule() {
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: false, notificationsAvailable: true, pendingCount: 1))
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: false, pendingCount: 1))
        XCTAssertFalse(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: true, pendingCount: 0))
        XCTAssertTrue(AppState.shouldMarkNotificationsDelivered(notify: true, notificationsAvailable: true, pendingCount: 1))
    }
}
