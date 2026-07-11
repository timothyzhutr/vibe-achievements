import Foundation
import SQLite3

public final class ReadOnlySQLiteSnapshot {
    public enum Error: Swift.Error, Equatable {
        case openFailed
        case prepareFailed
        case stepFailed
        case busy
        case transactionEnded
    }

    public final class ReadTransaction {
        private let lock = NSLock()
        private var database: OpaquePointer?

        fileprivate init(database: OpaquePointer) {
            self.database = database
        }

        public func stringRows(sql: String) throws -> [[String?]] {
            lock.lock()
            defer { lock.unlock() }
            guard let database else { throw Error.transactionEnded }

            var statement: OpaquePointer?
            let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            guard prepareResult == SQLITE_OK else {
                throw ReadOnlySQLiteSnapshot.mappedError(prepareResult, fallback: .prepareFailed)
            }
            defer { sqlite3_finalize(statement) }

            var rows: [[String?]] = []
            while true {
                let stepResult = sqlite3_step(statement)
                switch stepResult {
                case SQLITE_ROW:
                    rows.append(Self.stringRow(from: statement))
                case SQLITE_DONE:
                    return rows
                default:
                    throw ReadOnlySQLiteSnapshot.mappedError(stepResult, fallback: .stepFailed)
                }
            }
        }

        fileprivate func invalidate() {
            lock.lock()
            database = nil
            lock.unlock()
        }

        private static func stringRow(from statement: OpaquePointer?) -> [String?] {
            (0..<sqlite3_column_count(statement)).map { column in
                guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                      let text = sqlite3_column_text(statement, column) else {
                    return nil
                }
                return String(cString: text)
            }
        }
    }

    let temporaryDatabaseURL: URL

    private let temporaryDirectoryURL: URL
    private var database: OpaquePointer?

    public init(
        sourceURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        temporaryDirectoryURL = temporaryDirectory
            .appendingPathComponent("ReadOnlySQLiteSnapshot-\(UUID().uuidString)", isDirectory: true)
        temporaryDatabaseURL = temporaryDirectoryURL.appendingPathComponent("snapshot.sqlite")

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw Error.openFailed
        }

        do {
            try Self.backUp(sourceURL: sourceURL, destinationURL: temporaryDatabaseURL)
            database = try Self.openReadOnly(at: temporaryDatabaseURL)
            try Self.configureReadOnly(database)
        } catch {
            sqlite3_close(database)
            database = nil
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    public func withReadTransaction<Result>(
        _ body: (ReadTransaction) throws -> Result
    ) throws -> Result {
        guard let database else { throw Error.openFailed }
        try Self.executeControl("BEGIN DEFERRED;", on: database)
        let transaction = ReadTransaction(database: database)

        let result: Result
        do {
            result = try body(transaction)
        } catch {
            transaction.invalidate()
            try? Self.executeControl("ROLLBACK;", on: database)
            throw error
        }

        transaction.invalidate()
        try Self.executeControl("ROLLBACK;", on: database)
        return result
    }

    private static func backUp(sourceURL: URL, destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?

        let sourceResult = sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil)
        guard sourceResult == SQLITE_OK else {
            sqlite3_close(source)
            throw mappedError(sourceResult, fallback: .openFailed)
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 250)

        let destinationFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let destinationResult = sqlite3_open_v2(destinationURL.path, &destination, destinationFlags, nil)
        guard destinationResult == SQLITE_OK else {
            sqlite3_close(destination)
            throw mappedError(destinationResult, fallback: .openFailed)
        }
        defer { sqlite3_close(destination) }
        sqlite3_busy_timeout(destination, 250)

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw mappedError(sqlite3_errcode(destination), fallback: .stepFailed)
        }

        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE else {
            throw mappedError(stepResult, fallback: .stepFailed)
        }
        guard finishResult == SQLITE_OK else {
            throw mappedError(finishResult, fallback: .stepFailed)
        }
        try executeControl("PRAGMA journal_mode=DELETE;", on: destination)
    }

    private static func openReadOnly(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw mappedError(result, fallback: .openFailed)
        }
        sqlite3_busy_timeout(database, 250)
        return database
    }

    private static func configureReadOnly(_ database: OpaquePointer?) throws {
        try executeControl("PRAGMA query_only=ON;", on: database)
    }

    private static func executeControl(_ sql: String, on database: OpaquePointer?) throws {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw mappedError(prepareResult, fallback: .prepareFailed)
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            throw mappedError(stepResult, fallback: .stepFailed)
        }
    }

    private static func mappedError(_ result: Int32, fallback: Error) -> Error {
        switch result {
        case SQLITE_BUSY, SQLITE_LOCKED:
            return .busy
        default:
            return fallback
        }
    }
}
