import XCTest
import SQLite3
@testable import VibeAchievementsCore

final class OpenCodeSourceAdapterTests: XCTestCase {
    func testUsesXDGDataHomeAndDoesNotInspectAuthOrLogs() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let xdg = fixture.root.appendingPathComponent("xdg", isDirectory: true)
        let dataRoot = xdg.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try "not json".write(to: dataRoot.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dataRoot.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try "not a database".write(to: dataRoot.appendingPathComponent("logs/runtime.log"), atomically: true, encoding: .utf8)
        let database = dataRoot.appendingPathComponent("opencode.db")
        try fixture.makeCurrentDatabase(at: database, sessionID: "session-xdg")

        let adapter = OpenCodeSourceAdapter(
            home: fixture.root.appendingPathComponent("home"),
            environment: ["XDG_DATA_HOME": xdg.path],
            detectorVersion: "test"
        )

        let inventory = try adapter.discover()

        XCTAssertTrue(inventory.isComplete)
        XCTAssertEqual(inventory.records.map(\.stableID).count, 1)
        XCTAssertTrue(inventory.detectedRoots.contains(dataRoot))
        XCTAssertTrue(inventory.warnings.isEmpty)
        XCTAssertFalse(inventory.records.contains { $0.displayPath.contains("auth.json") })
        XCTAssertFalse(inventory.records.contains { $0.displayPath.contains("logs") })
    }

    func testUsesDefaultDataRootWhenXDGDataHomeIsAbsent() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root
            .appendingPathComponent("home", isDirectory: true)
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try fixture.makeCurrentDatabase(
            at: dataRoot.appendingPathComponent("opencode.db"),
            sessionID: "session-default"
        )

        let adapter = OpenCodeSourceAdapter(
            home: fixture.root.appendingPathComponent("home"),
            environment: [:],
            detectorVersion: "test"
        )

        let inventory = try adapter.discover()

        XCTAssertEqual(inventory.records.count, 1)
        XCTAssertTrue(inventory.detectedRoots.contains(dataRoot))
    }

    func testOPENCODEDBAcceptsAbsoluteRelativeAndChannelDatabases() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let absoluteDatabase = fixture.root.appendingPathComponent("absolute.db")
        let relativeDatabase = dataRoot.appendingPathComponent("relative.db")
        let channelDatabase = dataRoot.appendingPathComponent("opencode-beta.db")
        try fixture.makeCurrentDatabase(at: absoluteDatabase, sessionID: "absolute")
        try fixture.makeCurrentDatabase(at: dataRoot.appendingPathComponent("opencode.db"), sessionID: "primary")
        try fixture.makeCurrentDatabase(at: relativeDatabase, sessionID: "relative")
        try fixture.makeCurrentDatabase(at: channelDatabase, sessionID: "channel")

        let absoluteAdapter = OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: ["OPENCODE_DB": absoluteDatabase.path],
            detectorVersion: "test"
        )
        let relativeAdapter = OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: ["OPENCODE_DB": "relative.db"],
            detectorVersion: "test"
        )

        let absoluteInventory = try absoluteAdapter.discover()
        let relativeInventory = try relativeAdapter.discover()

        XCTAssertEqual(absoluteInventory.records.count, 3)
        XCTAssertEqual(relativeInventory.records.count, 3)
        XCTAssertTrue(absoluteInventory.records.contains { $0.displayPath == absoluteDatabase.path })
        XCTAssertTrue(relativeInventory.records.contains { $0.displayPath == relativeDatabase.path })
        XCTAssertTrue(relativeInventory.records.contains { URL(fileURLWithPath: $0.displayPath).lastPathComponent == channelDatabase.lastPathComponent })
    }

    func testCurrentGenerationWinsOverCompatibilityAndLegacyIsUsedOnlyForMissingSessions() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        let storage = dataRoot.appendingPathComponent("storage", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try fixture.makeCurrentAndCompatibilityDatabase(
            at: dataRoot.appendingPathComponent("opencode.db"),
            currentSessionID: "same-session",
            compatibilitySessionID: "compat-only"
        )
        try fixture.makeLegacySession(
            at: storage,
            projectID: "project-1",
            sessionID: "legacy-only"
        )
        try fixture.makeLegacySession(
            at: storage,
            projectID: "project-1",
            sessionID: "same-session"
        )

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        let recordIDs = inventory.records.map(\.stableID)
        XCTAssertEqual(recordIDs.count, 3)
        XCTAssertTrue(recordIDs.contains { $0.contains("same-session") && $0.contains("current") })
        XCTAssertTrue(recordIDs.contains { $0.contains("compat-only") && $0.contains("compatibility") })
        XCTAssertTrue(recordIDs.contains { $0.contains("legacy-only") })
        XCTAssertFalse(recordIDs.contains { $0.contains("same-session") && $0.contains("legacy") })
    }

    func testUnsupportedDatabaseProducesWarningWithoutOpeningOtherFiles() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let unsupported = dataRoot.appendingPathComponent("opencode.db")
        try fixture.makeUnsupportedDatabase(at: unsupported)

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertTrue(inventory.records.isEmpty)
        XCTAssertEqual(inventory.warnings.count, 1)
        XCTAssertEqual(inventory.warnings.first?.code, .schemaUnsupported)
        XCTAssertTrue(inventory.isComplete)
    }

    func testEmptySupportedDatabaseIsConnectedAndEmptyWithoutWarning() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try fixture.makeEmptyCurrentDatabase(at: dataRoot.appendingPathComponent("opencode.db"))

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertTrue(inventory.records.isEmpty)
        XCTAssertTrue(inventory.warnings.isEmpty)
        XCTAssertTrue(inventory.isComplete)
    }

    func testUnreadableDataRootEnumerationProducesIncompleteInventory() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try fixture.makeCurrentDatabase(
            at: dataRoot.appendingPathComponent("opencode.db"),
            sessionID: "hidden"
        )
        XCTAssertEqual(chmod(dataRoot.path, 0), 0)
        defer { _ = chmod(dataRoot.path, S_IRWXU) }

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertFalse(inventory.isComplete)
        XCTAssertEqual(inventory.warnings.map(\.code), [.permissionDenied])
    }

    func testUnavailableExplicitDatabaseOverrideProducesIncompleteInventory() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let missingOverride = fixture.root.appendingPathComponent("missing-override.db")

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: ["OPENCODE_DB": missingOverride.path],
            detectorVersion: "test"
        ).discover()

        XCTAssertFalse(inventory.isComplete)
        XCTAssertEqual(inventory.warnings.map(\.code), [.permissionDenied])
    }

    func testSchemaPrepareFailureIsNotReportedAsSourceBusy() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try fixture.makeIncompleteCurrentDatabase(at: dataRoot.appendingPathComponent("opencode.db"))

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertEqual(inventory.warnings.map(\.code), [.schemaUnsupported])
    }

    func testMalformedLegacySessionDoesNotHideOtherLegacySessions() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        let storage = dataRoot.appendingPathComponent("storage", isDirectory: true)
        try fixture.makeMalformedLegacySession(
            at: storage,
            projectID: "project-1",
            sessionID: "bad-session"
        )
        try fixture.makeLegacySession(
            at: storage,
            projectID: "project-1",
            sessionID: "good-session"
        )

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertEqual(inventory.records.map(\.stableID), ["legacy|project-1|good-session"])
        XCTAssertEqual(inventory.warnings.map(\.code), [.malformedRecord])
    }

    func testSameSessionIDDifferentChannelContentSelectsOneDeterministicRecord() throws {
        let fixture = try OpenCodeFixture()
        defer { fixture.remove() }
        let dataRoot = fixture.root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let primary = dataRoot.appendingPathComponent("opencode.db")
        let beta = dataRoot.appendingPathComponent("opencode-beta.db")
        try fixture.makeCurrentDatabase(at: primary, sessionID: "shared-session", text: "primary")
        try fixture.makeCurrentDatabase(at: beta, sessionID: "shared-session", text: "beta")

        let inventory = try OpenCodeSourceAdapter(
            dataRoot: dataRoot,
            environment: [:],
            detectorVersion: "test"
        ).discover()

        XCTAssertEqual(inventory.records.count, 1)
        XCTAssertEqual(
            inventory.records.first.map { URL(fileURLWithPath: $0.displayPath).lastPathComponent },
            beta.lastPathComponent
        )
        XCTAssertEqual(inventory.warnings.map(\.code), [.duplicateRecord])
    }
}

private final class OpenCodeFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeSourceAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeCurrentDatabase(at url: URL, sessionID: String, text: String = "hello") throws {
        let connection = try SQLiteFixtureConnection(url: url)
        try connection.execute("CREATE TABLE project (id TEXT PRIMARY KEY, worktree TEXT);")
        try connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try connection.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try connection.execute("INSERT INTO project VALUES ('project-1', '/worktree');")
        try connection.execute("INSERT INTO session VALUES ('\(sessionID)', 'project-1', '/session-directory', 'Fixture', 1000, 2000);")
        try connection.execute("INSERT INTO session_message VALUES ('message-1', '\(sessionID)', 'user', 1, 1000, 1000, '{\"role\":\"user\",\"content\":\"\(text)\"}');")
    }

    func makeCurrentAndCompatibilityDatabase(at url: URL, currentSessionID: String, compatibilitySessionID: String) throws {
        let connection = try SQLiteFixtureConnection(url: url)
        try connection.execute("CREATE TABLE project (id TEXT PRIMARY KEY, worktree TEXT);")
        try connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, directory TEXT, title TEXT, time_created INTEGER, time_updated INTEGER);")
        try connection.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try connection.execute("CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try connection.execute("CREATE TABLE part (id TEXT, message_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try connection.execute("INSERT INTO project VALUES ('project-1', '/worktree');")
        try connection.execute("INSERT INTO session VALUES ('\(currentSessionID)', 'project-1', '/session-directory', 'Current', 1000, 2000);")
        try connection.execute("INSERT INTO session VALUES ('\(compatibilitySessionID)', 'project-1', '/session-directory', 'Compatibility', 1000, 2000);")
        try connection.execute("INSERT INTO session_message VALUES ('message-1', '\(currentSessionID)', 'user', 1, 1000, 1000, '{\"role\":\"user\",\"content\":\"current\"}');")
        try connection.execute("INSERT INTO message VALUES ('compat-message', '\(compatibilitySessionID)', 1000, 1000, '{\"role\":\"user\"}');")
        try connection.execute("INSERT INTO part VALUES ('compat-part', 'compat-message', 1000, 1000, '{\"type\":\"text\",\"text\":\"compatibility\"}');")
    }

    func makeUnsupportedDatabase(at url: URL) throws {
        let connection = try SQLiteFixtureConnection(url: url)
        try connection.execute("CREATE TABLE unrelated (value TEXT);")
    }

    func makeEmptyCurrentDatabase(at url: URL) throws {
        let connection = try SQLiteFixtureConnection(url: url)
        try connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER, time_updated INTEGER);")
        try connection.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);")
    }

    func makeIncompleteCurrentDatabase(at url: URL) throws {
        let connection = try SQLiteFixtureConnection(url: url)
        try connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY);")
        try connection.execute("CREATE TABLE session_message (id TEXT, session_id TEXT);")
    }

    func makeLegacySession(at storage: URL, projectID: String, sessionID: String) throws {
        let projectURL = storage.appendingPathComponent("project", isDirectory: true)
            .appendingPathComponent("\(projectID).json")
        let sessionURL = storage.appendingPathComponent("session", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("\(sessionID).json")
        let messageURL = storage.appendingPathComponent("message", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("message-1.json")
        let partURL = storage.appendingPathComponent("part", isDirectory: true)
            .appendingPathComponent("message-1", isDirectory: true)
            .appendingPathComponent("part-1.json")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: messageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"id\":\"\(projectID)\",\"directory\":\"/legacy-project\"}".write(to: projectURL, atomically: true, encoding: .utf8)
        try "{\"id\":\"\(sessionID)\",\"messageIds\":[\"message-1\"]}".write(to: sessionURL, atomically: true, encoding: .utf8)
        try "{\"id\":\"message-1\",\"role\":\"user\",\"partIds\":[\"part-1\"]}".write(to: messageURL, atomically: true, encoding: .utf8)
        try "{\"id\":\"part-1\",\"type\":\"text\",\"text\":\"legacy\"}".write(to: partURL, atomically: true, encoding: .utf8)
    }

    func makeMalformedLegacySession(at storage: URL, projectID: String, sessionID: String) throws {
        let sessionURL = storage.appendingPathComponent("session", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("\(sessionID).json")
        try FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not-json".write(to: sessionURL, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class SQLiteFixtureConnection {
    private var database: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw FixtureError.sqlite
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
    }
}

private enum FixtureError: Error {
    case sqlite
}
