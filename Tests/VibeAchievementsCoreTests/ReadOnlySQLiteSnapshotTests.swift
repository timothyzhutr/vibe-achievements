import Foundation
import SQLite3
import XCTest
@testable import VibeAchievementsCore

final class ReadOnlySQLiteSnapshotTests: XCTestCase {
    func testSnapshotSeesCommittedRowsStillInLiveWAL() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }

        try fixture.execute("INSERT INTO messages (body) VALUES ('committed-in-wal');")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.databaseURL.path + "-wal"))

        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)

        let rows = try snapshot.withReadTransaction { transaction in
            try transaction.stringRows(sql: "SELECT body FROM messages ORDER BY rowid;")
        }
        XCTAssertEqual(rows, [["created-before-wal-row"], ["committed-in-wal"]])
    }

    func testQueryOnlyConnectionDeniesWrites() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)

        try snapshot.withReadTransaction { transaction in
            XCTAssertEqual(
                try transaction.stringRows(sql: "PRAGMA query_only;"),
                [["1"]]
            )
            XCTAssertEqual(
                try transaction.stringRows(sql: "PRAGMA busy_timeout;"),
                [["250"]]
            )
            XCTAssertThrowsError(
                try transaction.stringRows(sql: "INSERT INTO messages (body) VALUES ('denied');")
            ) { error in
                XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .stepFailed)
            }
        }
    }

    func testStepFailureUsesTypedError() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)

        XCTAssertThrowsError(
            try snapshot.withReadTransaction { transaction in
                try transaction.stringRows(sql: "SELECT abs(-9223372036854775808);")
            }
        ) { error in
            XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .stepFailed)
        }
    }

    func testOpenAndPrepareFailuresUseTypedErrors() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        XCTAssertThrowsError(try ReadOnlySQLiteSnapshot(sourceURL: missingURL)) { error in
            XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .openFailed)
        }

        let fixture = try WALFixture()
        defer { fixture.remove() }
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)

        XCTAssertThrowsError(
            try snapshot.withReadTransaction { transaction in
                try transaction.stringRows(sql: "SELECT FROM invalid syntax;")
            }
        ) { error in
            XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .prepareFailed)
        }
    }

    func testTemporaryStorageOpenFailureUsesTypedError() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(
            try ReadOnlySQLiteSnapshot(
                sourceURL: fixture.databaseURL,
                temporaryDirectory: fileURL
            )
        ) { error in
            XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .openFailed)
        }
    }

    func testBusyFailureUsesTypedError() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)
        let lock = try SQLiteConnection(path: snapshot.temporaryDatabaseURL.path)
        try lock.execute("BEGIN EXCLUSIVE;")
        defer { try? lock.execute("ROLLBACK;") }

        XCTAssertThrowsError(
            try snapshot.withReadTransaction { transaction in
                try transaction.stringRows(sql: "SELECT body FROM messages;")
            }
        ) { error in
            XCTAssertEqual(error as? ReadOnlySQLiteSnapshot.Error, .busy)
        }
    }

    func testTemporarySnapshotIsRemovedOnDeinit() throws {
        let fixture = try WALFixture()
        defer { fixture.remove() }
        var snapshot: ReadOnlySQLiteSnapshot? = try ReadOnlySQLiteSnapshot(sourceURL: fixture.databaseURL)
        let temporaryDatabaseURL = try XCTUnwrap(snapshot?.temporaryDatabaseURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDatabaseURL.path))
        snapshot = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDatabaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDatabaseURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDatabaseURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDatabaseURL.path + "-journal"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temporaryDatabaseURL.deletingLastPathComponent().path)
        )
    }
}

private final class WALFixture {
    let databaseURL: URL
    private let directoryURL: URL
    private let connection: SQLiteConnection

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadOnlySQLiteSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        databaseURL = directoryURL.appendingPathComponent("source.sqlite")
        connection = try SQLiteConnection(path: databaseURL.path)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA wal_autocheckpoint=0;")
        try execute("CREATE TABLE messages (body TEXT NOT NULL);")
        try execute("INSERT INTO messages (body) VALUES ('created-before-wal-row');")
    }

    func execute(_ sql: String) throws {
        try connection.execute(sql)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class SQLiteConnection {
    private var database: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &database) == SQLITE_OK else {
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

private enum FixtureError: Swift.Error {
    case sqlite
}
