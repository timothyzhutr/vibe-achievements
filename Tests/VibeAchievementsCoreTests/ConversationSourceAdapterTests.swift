import Foundation
import XCTest
@testable import VibeAchievementsCore

final class ConversationSourceAdapterTests: XCTestCase {
    func testRecordsWithSameStableIDDifferentSourceToolsHaveDifferentIdentities() {
        let locator = SourceRecordLocator.file(URL(fileURLWithPath: "/tmp/shared-record.jsonl"))
        let claudeRecord = ConversationSourceRecord(
            sourceTool: .claudeCode,
            stableID: "shared-record",
            displayPath: "/tmp/shared-record.jsonl",
            locator: locator,
            fingerprint: "fingerprint"
        )
        let codexRecord = ConversationSourceRecord(
            sourceTool: .codex,
            stableID: "shared-record",
            displayPath: "/tmp/shared-record.jsonl",
            locator: locator,
            fingerprint: "fingerprint"
        )

        XCTAssertNotEqual(claudeRecord.identity, codexRecord.identity)
    }
}
