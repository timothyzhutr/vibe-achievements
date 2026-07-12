import XCTest
@testable import VibeAchievementsCore

final class OpenCodeIntegrationTests: XCTestCase {
    func testOpenCodeRecordsIndexOnceAndUnchangedRescanDoesNotReparse() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        defer { try? FileManager.default.removeItem(at: database.directory) }
        try database.execute("CREATE TABLE project (id TEXT PRIMARY KEY, worktree TEXT);")
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try database.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("INSERT INTO project VALUES ('project-1', '/tmp/opencode-project');")
        try database.execute("INSERT INTO session VALUES ('session-1', 'project-1', '/tmp/opencode-project', 'Fixture', 1000, 2000);")
        try database.execute("INSERT INTO session_message VALUES ('user-1', 'session-1', 'user', 1, 1000, 1000, '{\"content\":\"hello\"}');")
        try database.execute("INSERT INTO session_message VALUES ('assistant-1', 'session-1', 'assistant', 2, 2000, 2000, '{\"content\":\"world\"}');")

        let adapter = OpenCodeSourceAdapter(dataRoot: database.directory, environment: [:], detectorVersion: "test")
        let store = try SQLiteStore(path: database.directory.appendingPathComponent("app.sqlite").path)

        let first = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-1")
        let second = try Indexer.index(adapters: [adapter], contracts: [], store: store, scanID: "scan-2")

        XCTAssertEqual(first.changedRecordCount, 1)
        XCTAssertEqual(second.changedRecordCount, 0)
        XCTAssertTrue(first.warnings.isEmpty)
        XCTAssertEqual(first.sourceStatuses.first?.state, .connected)
    }
}
