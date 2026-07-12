import XCTest
import SQLite3
@testable import VibeAchievementsCore

final class CursorLegacyStoreReaderTests: XCTestCase {
    func testParsesSelectedLegacyComposerAndWorkspaceFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace-id", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "{\"folder\":\"/tmp/legacy-project\"}".write(
            to: workspace.appendingPathComponent("workspace.json"),
            atomically: true,
            encoding: .utf8
        )
        let database = workspace.appendingPathComponent("state.vscdb")
        let value = #"{"allComposers":[{"composerId":"legacy-1","createdAt":1700000000000,"conversation":[{"type":1,"bubbleId":"u1","text":"Legacy hello"},{"type":2,"bubbleId":"a1","text":"Legacy answer"}]},{"composerId":"legacy-2","createdAt":1700000001000,"conversation":[]}] }"#
        try makeDatabase(at: database, value: value)

        let record = ConversationSourceRecord(
            sourceTool: .cursor,
            stableID: "cursor:workspace-id:legacy-1",
            displayPath: database.path,
            locator: .database(database: database, recordID: "legacy:legacy-1"),
            fingerprint: "test"
        )
        let parsed = try CursorLegacyStoreReader().parse(record)

        XCTAssertEqual(parsed.messages.map(\.text), ["Legacy hello", "Legacy answer"])
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/legacy-project")
        XCTAssertEqual(parsed.thread.sourceThreadID, "legacy-1")
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDatabase(at url: URL, value: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorLegacyFixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); INSERT INTO ItemTable VALUES ('composer.composerData', '\(escaped)');"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw CursorLegacyFixtureError.sqlite }
    }
}

private enum CursorLegacyFixtureError: Error {
    case sqlite
}
