import XCTest
import SQLite3
@testable import VibeAchievementsCore

final class CursorIntegrationTests: XCTestCase {
    func testCursorRecordsIndexOnceAndUnchangedRescanParsesNothing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationSupport = root.appendingPathComponent("Cursor", isDirectory: true)
        let globalStorage = applicationSupport.appendingPathComponent("User/globalStorage", isDirectory: true)
        let projects = root.appendingPathComponent(".cursor/projects/project/agent-transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: globalStorage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try makeDatabase(at: globalStorage.appendingPathComponent("state.vscdb"))
        try "{\"role\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}}\n"
            .write(to: projects.appendingPathComponent("conversation.jsonl"), atomically: true, encoding: .utf8)

        let adapter = CursorSourceAdapter(
            roots: CursorRoots(
                applicationSupport: applicationSupport,
                projects: root.appendingPathComponent(".cursor/projects")
            ),
            detectorVersion: "cursor-test"
        )
        let store = try SQLiteStore(path: root.appendingPathComponent("app.sqlite").path)

        let first = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        let second = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")

        XCTAssertEqual(first.changedRecordCount, 2)
        XCTAssertEqual(second.changedRecordCount, 0)
        XCTAssertTrue(first.warnings.isEmpty)
        XCTAssertEqual(first.sourceStatuses.first?.state, .connected)
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorIntegrationFixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let value = "{\"composerId\":\"composer-1\",\"createdAt\":1700000000000,\"conversation\":[]}"
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT); CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); INSERT INTO composerHeaders VALUES ('composer-1','workspace-1',1700000000000,1700000000000,0,0,1,0,'{}'); INSERT INTO cursorDiskKV VALUES ('composerData:composer-1','\(escaped)');"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw CursorIntegrationFixtureError.sqlite }
    }
}

private enum CursorIntegrationFixtureError: Error {
    case sqlite
}
