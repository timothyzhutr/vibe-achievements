import Foundation
import SQLite3

final class OpenCodeSQLiteTestDatabase {
    let directory: URL
    let url: URL
    private let database: OpaquePointer?

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeSQLiteTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("opencode.db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw OpenCodeTestError.sqlite
        }
        database = handle
    }

    deinit {
        sqlite3_close(database)
        try? FileManager.default.removeItem(at: directory)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw OpenCodeTestError.sqlite
        }
    }
}

func openCodeSQLQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

func writeOpenCodeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

enum OpenCodeTestError: Error {
    case sqlite
}
