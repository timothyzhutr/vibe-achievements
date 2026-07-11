import XCTest
@testable import VibeAchievementsCore

final class IndexerTests: XCTestCase {
    func testUnchangedRecordIsNotParsedAgain() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [record(id: "one", fingerprint: "fp-1")])

        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")

        XCTAssertEqual(adapter.parseCount, 1)
    }

    func testFailedRecordIsRetriedOnNextScan() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [record(id: "retry", fingerprint: "fp-1")])
        adapter.parseError = StubError.parse

        let failed = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        adapter.parseError = nil
        let retried = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")

        XCTAssertEqual(failed.warnings.count, 1)
        XCTAssertEqual(failed.warnings.first?.sourceTool, .claudeCode)
        XCTAssertEqual(failed.warnings.first?.recordID, "retry")
        XCTAssertTrue(retried.warnings.isEmpty)
        XCTAssertEqual(adapter.parseCount, 2)
    }

    func testAdapterDiscoveryFailureDoesNotBlockAnotherAdapter() throws {
        let store = try makeStore()
        let failed = StubAdapter(sourceTool: .claudeCode, records: [])
        failed.discoveryError = StubError.discovery
        let healthy = StubAdapter(sourceTool: .codex, records: [record(tool: .codex, id: "healthy", fingerprint: "fp")])

        let result = try Indexer.index(adapters: [failed, healthy], contracts: [], store: store, scanID: "scan")

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(healthy.parseCount, 1)
        XCTAssertTrue(try store.threadExists(id: "codex:healthy"))
    }

    func testRecordIsRemovedOnlyAfterTwoCompleteScansWhereItIsMissing() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [record(id: "gone", fingerprint: "fp")])
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        XCTAssertTrue(try store.threadExists(id: "claude_code:gone"))

        adapter.records = []
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")
        XCTAssertTrue(try store.threadExists(id: "claude_code:gone"))

        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-3")
        XCTAssertFalse(try store.threadExists(id: "claude_code:gone"))
    }

    func testMigratedFingerprintWithoutThreadIDIsParsedOnce() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        try store.recordFileFingerprint(
            path: "/tmp/.claude/projects/project/migrated.jsonl",
            fingerprint: "legacy-fp"
        )
        let reopened = try SQLiteStore(path: path)
        let adapter = StubAdapter(records: [record(id: "migrated", fingerprint: "legacy-fp")])

        _ = try Indexer.index(adapters: [adapter], contracts: [], store: reopened, scanID: "scan")

        XCTAssertEqual(adapter.parseCount, 1)
        XCTAssertEqual(
            try reopened.sourceRecord(identity: SourceRecordIdentity(sourceTool: .claudeCode, stableID: "migrated"))?.threadID,
            "claude_code:migrated"
        )
    }

    func testIncompleteInventoryNeverAdvancesMissingRecordDeletion() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [record(id: "safe", fingerprint: "fp")])
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")

        adapter.records = []
        adapter.warnings = [SourceWarning(
            sourceTool: .claudeCode,
            code: .sourceBusy,
            message: "Source is busy"
        )]
        let second = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-3")

        XCTAssertTrue(try store.threadExists(id: "claude_code:safe"))
        XCTAssertEqual(second.sourceStatuses.first?.state, .needsAttention)
    }

    func testExplicitlyPartialInventoryNeverAdvancesMissingRecordDeletion() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [record(id: "safe", fingerprint: "fp")])
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")

        adapter.records = []
        adapter.isComplete = false
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")
        _ = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-3")

        XCTAssertTrue(try store.threadExists(id: "claude_code:safe"))
    }

    func testStructuredSourceWarningFieldsArePreserved() throws {
        let store = try makeStore()
        let adapter = StubAdapter(records: [])
        adapter.warnings = [SourceWarning(
            sourceTool: .claudeCode,
            recordID: "session",
            code: .sourceBusy,
            message: "Source is busy"
        )]

        let result = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan")

        XCTAssertEqual(result.warnings.first?.sourceTool, .claudeCode)
        XCTAssertEqual(result.warnings.first?.recordID, "session")
        XCTAssertEqual(result.warnings.first?.code, .sourceBusy)
    }

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore(path: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
    }

    private func record(tool: SourceTool = .claudeCode, id: String, fingerprint: String) -> ConversationSourceRecord {
        ConversationSourceRecord(
            sourceTool: tool,
            stableID: id,
            displayPath: "/tmp/\(id).jsonl",
            locator: .file(URL(fileURLWithPath: "/tmp/\(id).jsonl")),
            fingerprint: fingerprint
        )
    }
}

private final class StubAdapter: ConversationSourceAdapter, @unchecked Sendable {
    let sourceTool: SourceTool
    let displayName: String
    var records: [ConversationSourceRecord]
    var warnings: [SourceWarning] = []
    var isComplete = true
    var discoveryError: Error?
    var parseError: Error?
    private(set) var parseCount = 0

    init(sourceTool: SourceTool = .claudeCode, records: [ConversationSourceRecord]) {
        self.sourceTool = sourceTool
        self.displayName = sourceTool.rawValue
        self.records = records
    }

    func discover() throws -> SourceInventory {
        if let discoveryError { throw discoveryError }
        return SourceInventory(records: records, warnings: warnings, detectedRoots: [], isComplete: isComplete)
    }

    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        parseCount += 1
        if let parseError { throw parseError }
        let thread = NormalizedThread(
            id: "\(sourceTool.rawValue):\(record.stableID)",
            sourceTool: sourceTool,
            sourceThreadID: record.stableID,
            sourcePath: record.displayPath,
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
        return ParsedTranscript(thread: thread, messages: [])
    }
}

private enum StubError: Error {
    case discovery
    case parse
}
