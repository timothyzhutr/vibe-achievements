import Foundation
import SQLite3

// The database handle and transaction state are only accessed while holding
// transactionScopeLock after initialization.
public final class ReadOnlySQLiteSnapshot: @unchecked Sendable {
    public enum Strategy: Sendable {
        case snapshot
        case direct
    }

    public enum Error: Swift.Error, Equatable {
        case openFailed
        case prepareFailed
        case stepFailed
        case busy
        case transactionEnded
        case transactionAlreadyActive
        case statementRejected
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
            guard Self.isAllowedReadStatement(sql) else { throw Error.statementRejected }

            var statement: OpaquePointer?
            let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            guard prepareResult == SQLITE_OK else {
                throw ReadOnlySQLiteSnapshot.mappedError(prepareResult, fallback: .prepareFailed)
            }
            guard let statement else { throw Error.statementRejected }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_stmt_readonly(statement) != 0 else { throw Error.statementRejected }

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

        private static func isAllowedReadStatement(_ sql: String) -> Bool {
            guard let (keyword, remainder) = leadingKeywordAndRemainder(in: sql) else { return false }
            switch keyword {
            case "SELECT", "WITH", "EXPLAIN":
                return true
            case "PRAGMA":
                return isAllowedPragma(remainder)
            default:
                return false
            }
        }

        private static func isAllowedPragma(_ remainder: String) -> Bool {
            let value = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("=") else { return false }

            let nameEnd = value.firstIndex { character in
                character.isWhitespace || character == "(" || character == ";"
            } ?? value.endIndex
            let qualifiedName = value[..<nameEnd].uppercased()
            let name = qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
            let argument = value[nameEnd...].trimmingCharacters(in: .whitespacesAndNewlines)

            switch name {
            case "QUERY_ONLY", "BUSY_TIMEOUT", "USER_VERSION", "SCHEMA_VERSION":
                return argument.isEmpty || argument == ";"
            case "TABLE_INFO", "TABLE_XINFO":
                return argument.isEmpty || argument == ";"
                    || (argument.hasPrefix("(") && (argument.hasSuffix(")") || argument.hasSuffix(");")))
            default:
                return false
            }
        }

        private static func leadingKeywordAndRemainder(in sql: String) -> (keyword: String, remainder: String)? {
            let bytes = Array(sql.utf8)
            var index = 0

            while index < bytes.count {
                while index < bytes.count, isWhitespace(bytes[index]) {
                    index += 1
                }

                if index + 1 < bytes.count, bytes[index] == 45, bytes[index + 1] == 45 {
                    index += 2
                    while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                        index += 1
                    }
                    continue
                }

                if index + 1 < bytes.count, bytes[index] == 47, bytes[index + 1] == 42 {
                    index += 2
                    while index + 1 < bytes.count,
                          !(bytes[index] == 42 && bytes[index + 1] == 47) {
                        index += 1
                    }
                    guard index + 1 < bytes.count else { return nil }
                    index += 2
                    continue
                }

                break
            }

            let start = index
            while index < bytes.count,
                  (bytes[index] >= 65 && bytes[index] <= 90 || bytes[index] >= 97 && bytes[index] <= 122) {
                index += 1
            }
            guard start < index else { return nil }
            return (
                String(decoding: bytes[start..<index], as: UTF8.self).uppercased(),
                String(decoding: bytes[index...], as: UTF8.self)
            )
        }

        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 32 || (byte >= 9 && byte <= 13)
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

    private let temporaryDirectoryURL: URL?
    private let transactionScopeLock = NSRecursiveLock()
    private var database: OpaquePointer?
    private var transactionActive = false

    public init(
        sourceURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        strategy: Strategy = .snapshot
    ) throws {
        if strategy == .direct {
            temporaryDirectoryURL = nil
            temporaryDatabaseURL = sourceURL
            do {
                database = try Self.openReadOnly(at: sourceURL)
                try Self.configureReadOnly(database)
            } catch {
                sqlite3_close(database)
                database = nil
                throw error
            }
            return
        }

        let snapshotDirectoryURL = temporaryDirectory
            .appendingPathComponent("ReadOnlySQLiteSnapshot-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectoryURL = snapshotDirectoryURL
        temporaryDatabaseURL = snapshotDirectoryURL.appendingPathComponent("snapshot.sqlite")

        do {
            try FileManager.default.createDirectory(
                at: snapshotDirectoryURL,
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
            try? FileManager.default.removeItem(at: snapshotDirectoryURL)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    public func withReadTransaction<Result>(
        _ body: (ReadTransaction) throws -> Result
    ) throws -> Result {
        transactionScopeLock.lock()
        defer { transactionScopeLock.unlock() }
        guard !transactionActive else { throw Error.transactionAlreadyActive }
        guard let database else { throw Error.openFailed }
        transactionActive = true
        defer { transactionActive = false }
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
