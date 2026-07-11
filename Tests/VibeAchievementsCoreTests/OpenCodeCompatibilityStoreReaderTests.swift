import XCTest
@testable import VibeAchievementsCore

final class OpenCodeCompatibilityStoreReaderTests: XCTestCase {
    func testOrdersMessagesAndTextPartsWithPromotedIDs() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try database.execute("CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("CREATE TABLE part (id TEXT, message_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("INSERT INTO session VALUES ('session-compat', '/compat/project', 'Compat', 1000, 4000);")
        try database.execute("INSERT INTO message VALUES ('message-b', 'session-compat', 1000, 1100, '{\"role\":\"assistant\"}');")
        try database.execute("INSERT INTO message VALUES ('message-a', 'session-compat', 1000, 1200, '{\"role\":\"user\"}');")
        try database.execute("INSERT INTO part VALUES ('part-b', 'message-a', 1000, 1000, '{\"type\":\"text\",\"text\":\"second\"}');")
        try database.execute("INSERT INTO part VALUES ('part-a', 'message-a', 1000, 1000, '{\"type\":\"text\",\"text\":\"first\"}');")
        try database.execute("INSERT INTO part VALUES ('tool', 'message-b', 1000, 1000, '{\"type\":\"tool\",\"text\":\"ignore\"}');")
        try database.execute("INSERT INTO part VALUES ('part-c', 'message-b', 2000, 2000, '{\"type\":\"text\",\"text\":\"answer\"}');")

        let parsed = try OpenCodeCompatibilityStoreReader().parse(databaseURL: database.url, sessionID: "session-compat")

        XCTAssertEqual(parsed.thread.projectPath, "/compat/project")
        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), ["message-a", "message-b"])
        XCTAssertEqual(parsed.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(parsed.messages.map(\.text), ["first\nsecond", "answer"])
        XCTAssertEqual(parsed.messages.map(\.timestamp), [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 1)])
        XCTAssertEqual(parsed.thread.messageCount, 2)
    }

    func testUsesMessageTextWhenNoPartsExist() throws {
        let database = try OpenCodeSQLiteTestDatabase()
        try database.execute("CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try database.execute("CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("CREATE TABLE part (id TEXT, message_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try database.execute("INSERT INTO session VALUES ('session-text', '/tmp/project', 'Text', 1000, 1000);")
        try database.execute("INSERT INTO message VALUES ('message-1', 'session-text', 1000, 1000, '{\"role\":\"user\",\"text\":\"inline\"}');")

        let parsed = try OpenCodeCompatibilityStoreReader().parse(databaseURL: database.url, sessionID: "session-text")

        XCTAssertEqual(parsed.messages.map(\.text), ["inline"])
    }
}
