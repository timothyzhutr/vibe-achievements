import Foundation

public struct CursorLegacyStoreReader: Sendable {
    public init() {}

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == .cursor,
              case let .database(database, locatorID) = record.locator,
              locatorID.hasPrefix("legacy:")
        else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        let composerID = String(locatorID.dropFirst("legacy:".count))
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: database)
        let rows = try snapshot.withReadTransaction { transaction in
            try transaction.stringRows(sql: "SELECT value FROM ItemTable WHERE key = 'composer.composerData';")
        }
        guard let value = cell(rows.first ?? [], 0),
              let data = value.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CursorLegacyReaderError.missingComposerData
        }
        let composers = (root["allComposers"] as? [[String: Any]]) ?? [root]
        guard let composer = composers.first(where: { $0["composerId"] as? String == composerID }) else {
            throw CursorLegacyReaderError.missingComposer
        }
        let workspaceJSON = database.deletingLastPathComponent().appendingPathComponent("workspace.json")
        let projectPath = try workspaceProjectPath(from: workspaceJSON)
        let bubbles = composer["conversation"] as? [[String: Any]] ?? []
        return CursorConversationNormalizer.parse(
            composer: composer,
            bubbles: bubbles,
            stableID: record.stableID,
            sourcePath: record.displayPath,
            sourceThreadID: composerID,
            fallbackProjectPath: projectPath,
            rawType: "cursor.legacy"
        )
    }

    private func workspaceProjectPath(from url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return [object["folder"], object["workspaceFolder"], object["uri"]]
            .compactMap { $0 as? String }
            .first { $0.hasPrefix("/") }
    }
}

private enum CursorLegacyReaderError: Error {
    case missingComposerData
    case missingComposer
}

private func cell(_ row: [String?], _ index: Int) -> String? {
    guard row.indices.contains(index) else { return nil }
    return row[index]
}
