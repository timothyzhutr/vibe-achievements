import Foundation
import XCTest
@testable import VibeAchievementsCore

final class ConversationSourceAdapterTests: XCTestCase {
    func testAdapterCanImplementUnlabeledParseRequirement() {
        let adapter: any ConversationSourceAdapter = UnlabeledParseAdapter()

        XCTAssertEqual(adapter.sourceTool, .codex)
    }

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

private struct UnlabeledParseAdapter: ConversationSourceAdapter {
    let sourceTool = SourceTool.codex
    let displayName = "Codex"

    func discover() throws -> SourceInventory {
        SourceInventory(records: [], warnings: [], detectedRoots: [])
    }

    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        fatalError("Not needed for protocol conformance test")
    }
}
