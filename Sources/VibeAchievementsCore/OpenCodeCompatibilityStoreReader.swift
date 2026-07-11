import Foundation

public struct OpenCodeCompatibilityStoreReader: Sendable {
    public init() {}

    public func parse(databaseURL: URL, sessionID: String) throws -> ParsedTranscript {
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: databaseURL)
        return try snapshot.withReadTransaction { transaction in
            let session = try readSession(transaction: transaction, sessionID: sessionID)
            let rows = try transaction.stringRows(sql: "SELECT m.id, m.time_created, m.time_updated, m.data, p.id, p.time_created, p.time_updated, p.data FROM message m LEFT JOIN part p ON p.message_id = m.id WHERE m.session_id = \(OpenCodeSupport.sqlQuote(sessionID)) ORDER BY m.time_created, m.id, p.time_created, p.id;")
            guard !rows.isEmpty else { throw Error.missingMessages }

            var groups: [String: MessageGroup] = [:]
            var orderedIDs: [String] = []
            for row in rows {
                guard let messageID = OpenCodeSupport.value(row, at: 0), let messageData = OpenCodeSupport.jsonObject(OpenCodeSupport.value(row, at: 3)) else {
                    continue
                }
                if groups[messageID] == nil {
                    var promoted = messageData
                    promoted["id"] = promoted["id"] ?? messageID
                    promoted["session_id"] = promoted["session_id"] ?? sessionID
                    if let created = OpenCodeSupport.value(row, at: 1) { promoted["time_created"] = promoted["time_created"] ?? created }
                    if let updated = OpenCodeSupport.value(row, at: 2) { promoted["time_updated"] = promoted["time_updated"] ?? updated }
                    groups[messageID] = MessageGroup(
                        id: messageID,
                        object: promoted,
                        timestamp: OpenCodeSupport.date(promoted, keys: ["time_created", "timestamp"]),
                        parts: [],
                        inlineText: OpenCodeSupport.text(from: promoted["text"] ?? promoted["content"]),
                        tokenCount: OpenCodeSupport.tokens(from: promoted)
                    )
                    orderedIDs.append(messageID)
                }

                guard let partID = OpenCodeSupport.value(row, at: 4), let partData = OpenCodeSupport.jsonObject(OpenCodeSupport.value(row, at: 7)) else {
                    continue
                }
                var promotedPart = partData
                promotedPart["id"] = promotedPart["id"] ?? partID
                promotedPart["message_id"] = promotedPart["message_id"] ?? messageID
                if let created = OpenCodeSupport.value(row, at: 5) { promotedPart["time_created"] = promotedPart["time_created"] ?? created }
                if let updated = OpenCodeSupport.value(row, at: 6) { promotedPart["time_updated"] = promotedPart["time_updated"] ?? updated }
                groups[messageID]?.parts.append(promotedPart)
            }

            var drafts: [OpenCodeMessageDraft] = []
            var fallbackTokenTotal = 0
            for messageID in orderedIDs {
                guard let group = groups[messageID],
                      let role = OpenCodeSupport.role(from: OpenCodeSupport.string(group.object, keys: ["role", "type"])) else {
                    continue
                }
                let partText = group.parts.compactMap { part -> String? in
                    guard OpenCodeSupport.string(part, keys: ["type"]) == "text" else { return nil }
                    let text = OpenCodeSupport.text(from: part["text"] ?? part["content"])
                    return text.isEmpty ? nil : text
                }.joined(separator: "\n")
                let text = partText.isEmpty ? group.inlineText : partText
                guard !text.isEmpty else { continue }
                let partTokens = group.parts.reduce(0) { total, part in total + OpenCodeSupport.tokens(from: part) }
                let tokenCount = group.tokenCount > 0 ? group.tokenCount : partTokens
                if role == .assistant { fallbackTokenTotal += tokenCount }
                drafts.append(OpenCodeMessageDraft(
                    id: group.id,
                    role: role,
                    timestamp: group.timestamp,
                    text: text,
                    rawType: "message.\(OpenCodeSupport.string(group.object, keys: ["role", "type"]) ?? "unknown")",
                    tokenCount: tokenCount
                ))
            }

            return OpenCodeSupport.transcript(
                sessionID: sessionID,
                sourcePath: databaseURL.path,
                projectPath: session.directory,
                title: session.title,
                createdAt: OpenCodeSupport.date(milliseconds: session.createdAt),
                updatedAt: OpenCodeSupport.date(milliseconds: session.updatedAt),
                drafts: drafts,
                rawTokenCount: fallbackTokenTotal > 0 ? fallbackTokenTotal : nil
            )
        }
    }

    private struct SessionRow {
        let directory: String?
        let title: String?
        let createdAt: String?
        let updatedAt: String?
    }

    private struct MessageGroup {
        let id: String
        let object: [String: Any]
        let timestamp: Date?
        var parts: [[String: Any]]
        let inlineText: String
        let tokenCount: Int
    }

    private func readSession(transaction: ReadOnlySQLiteSnapshot.ReadTransaction, sessionID: String) throws -> SessionRow {
        let rows = try transaction.stringRows(sql: "SELECT directory, title, time_created, time_updated FROM session WHERE id = \(OpenCodeSupport.sqlQuote(sessionID)) LIMIT 1;")
        guard let row = rows.first else { throw Error.missingSession }
        return SessionRow(
            directory: OpenCodeSupport.value(row, at: 0),
            title: OpenCodeSupport.value(row, at: 1),
            createdAt: OpenCodeSupport.value(row, at: 2),
            updatedAt: OpenCodeSupport.value(row, at: 3)
        )
    }

    private enum Error: Swift.Error {
        case missingSession
        case missingMessages
    }
}
