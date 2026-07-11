import XCTest
@testable import VibeAchievementsCore

final class OpenCodeCurrentStoreReaderTests: XCTestCase {
    func testOrdersSessionMessagesBySeqAndUsesSessionTokensOnce() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        try database.execute("CREATE TABLE project (id TEXT PRIMARY KEY, worktree TEXT);")
        try database.execute("CREATE TABLE project_directory (project_id TEXT, directory TEXT, worktree TEXT);")
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER, tokens TEXT);")
        try database.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("INSERT INTO project VALUES ('project-1', '/project/worktree');")
        try database.execute("INSERT INTO project_directory VALUES ('project-1', '/project/directory', '/directory/worktree');")
        try database.execute("INSERT INTO session VALUES ('session-1', 'project-1', '/session/directory', 'A title', 1000, 3000, '{\"input\":100,\"output\":50}');")
        try database.execute("INSERT INTO session_message VALUES ('assistant-1', 'session-1', 'assistant', 1, 2000, 2100, '{\"content\":[{\"type\":\"text\",\"text\":\"first\"},{\"type\":\"tool_use\",\"name\":\"shell\"},{\"type\":\"text\",\"text\":\"response\"}],\"tokens\":{\"input\":3,\"output\":4}}');")
        try database.execute("INSERT INTO session_message VALUES ('user-1', 'session-1', 'user', 2, 1000, 1100, '{\"content\":\"prompt\"}');")
        try database.execute("INSERT INTO session_message VALUES ('system-1', 'session-1', 'system', 3, 3000, 3000, '{\"content\":\"not a turn\"}');")

        let parsed = try OpenCodeCurrentStoreReader().parse(databaseURL: database.url, sessionID: "session-1")

        XCTAssertEqual(parsed.thread.id, "opencode:session-1")
        XCTAssertEqual(parsed.thread.sourcePath, database.url.path)
        XCTAssertEqual(parsed.thread.projectPath, "/project/worktree")
        XCTAssertEqual(parsed.thread.title, "A title")
        XCTAssertEqual(parsed.thread.createdAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(parsed.thread.updatedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(parsed.thread.rawTokenCount, 150)
        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), ["assistant-1", "user-1"])
        XCTAssertEqual(parsed.messages.map(\.role), [.assistant, .user])
        XCTAssertEqual(parsed.messages.map(\.text), ["first\nresponse", "prompt"])
        XCTAssertEqual(parsed.thread.messageCount, 2)
        XCTAssertEqual(parsed.thread.userTurnCount, 1)
        XCTAssertEqual(parsed.thread.assistantTurnCount, 1)
    }

    func testSumsNonCumulativeAssistantTokensWhenSessionAggregateIsAbsent() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try database.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("INSERT INTO session VALUES ('session-2', '/tmp/project', 'Tokens', 1000, 2000);")
        try database.execute("INSERT INTO session_message VALUES ('assistant-1', 'session-2', 'assistant', 1, 1000, 1000, '{\"content\":\"one\",\"tokens\":{\"input\":5,\"output\":7}}');")
        try database.execute("INSERT INTO session_message VALUES ('assistant-2', 'session-2', 'assistant', 2, 2000, 2000, '{\"content\":\"two\",\"tokens\":{\"input\":2,\"output\":3}}');")

        let parsed = try OpenCodeCurrentStoreReader().parse(databaseURL: database.url, sessionID: "session-2")

        XCTAssertEqual(parsed.thread.rawTokenCount, 17)
    }

    func testRejectsMissingSession() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try database.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")

        XCTAssertThrowsError(
            try OpenCodeCurrentStoreReader().parse(databaseURL: database.url, sessionID: "missing")
        )
    }
}
