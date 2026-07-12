import XCTest
import SQLite3
@testable import VibeAchievementsCore

final class CursorGlobalStoreReaderTests: XCTestCase {
    func testParsesInlineConversationInOrderWithRolesAndProjectPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("state.vscdb")
        let composer = "composer-inline"
        let json = #"""
        {
          "composerId":"composer-inline",
          "createdAt":1700000000000,
          "context":{"folderSelections":[{"uri":"/tmp/cursor-project"}]},
          "conversation":[
            {"type":1,"bubbleId":"user-1","text":"Build the thing","createdAt":"2026-07-11T01:00:00.000Z"},
            {"type":2,"bubbleId":"assistant-1","text":"Absolutely.","createdAt":"2026-07-11T01:00:01.000Z"},
            {"type":3,"bubbleId":"tool-1","text":"ignored"}
          ]
        }
        """#
        try makeDatabase(at: database, composerID: composer, value: json)

        let record = ConversationSourceRecord(
            sourceTool: .cursor,
            stableID: "cursor:workspace-1:\(composer)",
            displayPath: database.path,
            locator: .database(database: database, recordID: "global:\(composer)"),
            fingerprint: "test"
        )
        let parsed = try CursorGlobalStoreReader().parse(record)

        XCTAssertEqual(parsed.thread.id, record.stableID)
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/cursor-project")
        XCTAssertEqual(parsed.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), ["user-1", "assistant-1"])
        XCTAssertEqual(parsed.messages.map(\.text), ["Build the thing", "Absolutely."])
        XCTAssertEqual(parsed.messages.map(\.id), ["user-1", "assistant-1"])
        XCTAssertEqual(parsed.thread.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testReadsExactBubbleKeysWhenComposerConversationIsEmpty() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("state.vscdb")
        let composer = "composer-bubbles"
        let metadata = #"{"composerId":"composer-bubbles","conversation":[]}"#
        let first = #"{"type":1,"bubbleId":"user-1","text":"First","createdAt":"2026-07-11T01:00:00.000Z"}"#
        let second = #"{"type":2,"bubbleId":"assistant-1","rawText":"Second","createdAt":"2026-07-11T01:00:01.000Z"}"#
        try makeDatabase(at: database, composerID: composer, value: metadata, bubbles: [first, second])

        let record = ConversationSourceRecord(
            sourceTool: .cursor,
            stableID: "cursor:workspace-1:\(composer)",
            displayPath: database.path,
            locator: .database(database: database, recordID: "global:\(composer)"),
            fingerprint: "test"
        )
        let parsed = try CursorGlobalStoreReader().parse(record)

        XCTAssertEqual(parsed.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(parsed.messages.map(\.text), ["First", "Second"])
    }

    func testInvalidLocatorIsRejected() throws {
        let record = ConversationSourceRecord(
            sourceTool: .cursor,
            stableID: "cursor:workspace:composer",
            displayPath: "/tmp/transcript.jsonl",
            locator: .file(URL(fileURLWithPath: "/tmp/transcript.jsonl")),
            fingerprint: "test"
        )

        XCTAssertThrowsError(try CursorGlobalStoreReader().parse(record)) { error in
            XCTAssertEqual(error as? ConversationSourceAdapterError, .invalidRecord)
        }
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDatabase(
        at url: URL,
        composerID: String,
        value: String,
        bubbles: [String] = []
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorFixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let metadata = value.replacingOccurrences(of: "'", with: "''")
        var sql = """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES ('composerData:\(composerID)', '\(metadata)');
        """
        for (index, bubble) in bubbles.enumerated() {
            let escaped = bubble.replacingOccurrences(of: "'", with: "''")
            sql += "INSERT INTO cursorDiskKV VALUES ('bubbleId:\(composerID):bubble-\(index)', '\(escaped)');"
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw CursorFixtureError.sqlite }
    }
}

private enum CursorFixtureError: Error {
    case sqlite
}
