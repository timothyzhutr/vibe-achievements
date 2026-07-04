import XCTest
@testable import VibeAchievementsApp
import VibeAchievementsCore

final class AppStateTests: XCTestCase {
    func testWarningsDoNotSuppressUnlockNotifications() {
        XCTAssertTrue(AppState.shouldSendUnlockNotifications(sendNotifications: true, hardError: nil, newUnlockCount: 1))
        XCTAssertFalse(AppState.shouldSendUnlockNotifications(sendNotifications: true, hardError: "Scan failed", newUnlockCount: 1))
        XCTAssertFalse(AppState.shouldSendUnlockNotifications(sendNotifications: true, hardError: nil, newUnlockCount: 0))
        XCTAssertFalse(AppState.shouldSendUnlockNotifications(sendNotifications: false, hardError: nil, newUnlockCount: 1))
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
