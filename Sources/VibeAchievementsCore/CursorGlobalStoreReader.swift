import Foundation

public struct CursorGlobalStoreReader: Sendable {
    public init() {}

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == .cursor,
              case let .database(database, locatorID) = record.locator,
              let separator = locatorID.firstIndex(of: ":"),
              locatorID[..<separator] != "legacy"
        else {
            throw ConversationSourceAdapterError.invalidRecord
        }

        let composerID = String(locatorID[locatorID.index(after: separator)...])
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: database)
        guard let composer = try readJSONObject(key: "composerData:\(composerID)", from: snapshot) else {
            throw CursorReaderError.missingComposer
        }
        let bubbles = try readBubbles(composer: composer, composerID: composerID, from: snapshot)
        return CursorConversationNormalizer.parse(
            composer: composer,
            bubbles: bubbles,
            stableID: record.stableID,
            sourcePath: record.displayPath,
            sourceThreadID: composerID,
            fallbackProjectPath: nil
        )
    }

    private func readBubbles(
        composer: [String: Any],
        composerID: String,
        from snapshot: ReadOnlySQLiteSnapshot
    ) throws -> [[String: Any]] {
        if let inline = composer["conversation"] as? [[String: Any]], !inline.isEmpty {
            return inline
        }

        let keys = try snapshot.withReadTransaction { transaction in
            try transaction.stringRows(sql: """
            SELECT key FROM cursorDiskKV
            WHERE key LIKE \(sqlLiteral("bubbleId:\(composerID):%"))
            ORDER BY key;
            """)
        }.compactMap { cell($0, 0) }

        var bubbles: [[String: Any]] = []
        for key in keys {
            guard let bubble = try readJSONObject(key: key, from: snapshot) else { continue }
            bubbles.append(bubble)
        }
        return bubbles.sorted { lhs, rhs in
            guard let left = CursorConversationNormalizer.date(from: lhs["createdAt"]),
                  let right = CursorConversationNormalizer.date(from: rhs["createdAt"]) else {
                return false
            }
            return left < right
        }
    }

    private func readJSONObject(key: String, from snapshot: ReadOnlySQLiteSnapshot) throws -> [String: Any]? {
        let rows = try snapshot.withReadTransaction { transaction in
            try transaction.stringRows(sql: "SELECT value FROM cursorDiskKV WHERE key = \(sqlLiteral(key));")
        }
        guard let value = cell(rows.first ?? [], 0),
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}

private enum CursorReaderError: Error {
    case missingComposer
}

private func sqlLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

private func cell(_ row: [String?], _ index: Int) -> String? {
    guard row.indices.contains(index) else { return nil }
    return row[index]
}
