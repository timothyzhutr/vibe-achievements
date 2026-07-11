import Foundation

public struct OpenCodeCurrentStoreReader: Sendable {
    public init() {}

    public func parse(databaseURL: URL, sessionID: String) throws -> ParsedTranscript {
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: databaseURL)
        return try snapshot.withReadTransaction { transaction in
            let quotedSessionID = OpenCodeSupport.sqlQuote(sessionID)
            let session = try readSession(transaction: transaction, sessionID: sessionID)
            let messages = try transaction.stringRows(sql: "SELECT id, type, seq, time_created, time_updated, data FROM session_message WHERE session_id = \(quotedSessionID) ORDER BY seq;")
            guard !messages.isEmpty else { throw Error.missingSessionMessages }

            let projectPath = try projectPath(
                transaction: transaction,
                projectID: session.projectID,
                sessionDirectory: session.directory
            )
            var drafts: [OpenCodeMessageDraft] = []
            var messageTokenTotal = 0
            for row in messages {
                guard let id = OpenCodeSupport.value(row, at: 0), let type = OpenCodeSupport.value(row, at: 1), let data = OpenCodeSupport.jsonObject(OpenCodeSupport.value(row, at: 5)) else {
                    continue
                }
                var promoted = data
                promoted["id"] = promoted["id"] ?? id
                promoted["type"] = promoted["type"] ?? type
                if let created = OpenCodeSupport.value(row, at: 3) { promoted["time_created"] = promoted["time_created"] ?? created }
                if let updated = OpenCodeSupport.value(row, at: 4) { promoted["time_updated"] = promoted["time_updated"] ?? updated }

                let nested = promoted["message"] as? [String: Any]
                let role = OpenCodeSupport.role(from: OpenCodeSupport.string(nested ?? promoted, keys: ["role", "type"]) ?? type)
                guard let role else { continue }
                let content = OpenCodeSupport.text(from: nested?["content"] ?? promoted["content"] ?? promoted["text"])
                guard !content.isEmpty else { continue }
                let tokenCount = OpenCodeSupport.tokens(from: nested ?? promoted)
                if role == .assistant { messageTokenTotal += tokenCount }
                drafts.append(OpenCodeMessageDraft(
                    id: id,
                    role: role,
                    timestamp: OpenCodeSupport.date(promoted, keys: ["time_created", "timestamp"]),
                    text: content,
                    rawType: "session_message.\(type)",
                    tokenCount: tokenCount
                ))
            }

            let sessionTokenTotal = session.tokens.map { OpenCodeSupport.tokenCount(from: $0) }
            let rawTokenCount = sessionTokenTotal.map { $0 > 0 ? $0 : nil } ?? (messageTokenTotal > 0 ? messageTokenTotal : nil)
            return OpenCodeSupport.transcript(
                sessionID: sessionID,
                sourcePath: databaseURL.path,
                projectPath: projectPath,
                title: session.title,
                createdAt: OpenCodeSupport.date(milliseconds: session.createdAt),
                updatedAt: OpenCodeSupport.date(milliseconds: session.updatedAt),
                drafts: drafts,
                rawTokenCount: rawTokenCount
            )
        }
    }

    private struct SessionRow {
        let projectID: String?
        let directory: String?
        let title: String?
        let createdAt: String?
        let updatedAt: String?
        let tokens: Any?
    }

    private func readSession(transaction: ReadOnlySQLiteSnapshot.ReadTransaction, sessionID: String) throws -> SessionRow {
        let quoted = OpenCodeSupport.sqlQuote(sessionID)
        let rows: [[String?]]
        do {
            rows = try transaction.stringRows(sql: "SELECT project_id, directory, title, time_created, time_updated, tokens FROM session WHERE id = \(quoted) LIMIT 1;")
        } catch {
            do {
                rows = try transaction.stringRows(sql: "SELECT project_id, directory, title, time_created, time_updated FROM session WHERE id = \(quoted) LIMIT 1;")
            } catch {
                do {
                    rows = try transaction.stringRows(sql: "SELECT directory, title, time_created, time_updated, tokens FROM session WHERE id = \(quoted) LIMIT 1;")
                } catch {
                    rows = try transaction.stringRows(sql: "SELECT directory, title, time_created, time_updated FROM session WHERE id = \(quoted) LIMIT 1;")
                }
            }
        }
        guard let row = rows.first else { throw Error.missingSession }
        let hasProjectColumn = row.count >= 6
        let tokensIndex = hasProjectColumn ? 5 : (row.count >= 5 ? 4 : -1)
        let tokens: Any? = tokensIndex >= 0
            ? OpenCodeSupport.value(row, at: tokensIndex).flatMap { OpenCodeSupport.jsonObject($0) }
            : nil
        return SessionRow(
            projectID: hasProjectColumn ? OpenCodeSupport.value(row, at: 0) : nil,
            directory: OpenCodeSupport.value(row, at: hasProjectColumn ? 1 : 0),
            title: OpenCodeSupport.value(row, at: hasProjectColumn ? 2 : 1),
            createdAt: OpenCodeSupport.value(row, at: hasProjectColumn ? 3 : 2),
            updatedAt: OpenCodeSupport.value(row, at: hasProjectColumn ? 4 : 3),
            tokens: tokens
        )
    }

    private func projectPath(
        transaction: ReadOnlySQLiteSnapshot.ReadTransaction,
        projectID: String?,
        sessionDirectory: String?
    ) throws -> String? {
        if let projectID {
            let quoted = OpenCodeSupport.sqlQuote(projectID)
            if let row = try? transaction.stringRows(sql: "SELECT worktree FROM project WHERE id = \(quoted) LIMIT 1;").first,
               let worktree = row.first ?? nil, !worktree.isEmpty {
                return worktree
            }
            if let values = try? transaction.stringRows(sql: "SELECT worktree, directory FROM project_directory WHERE project_id = \(quoted) ORDER BY worktree, directory LIMIT 1;").first,
               let path = values.compactMap({ $0 }).first, !path.isEmpty {
                return path
            }
        }
        return sessionDirectory
    }

    private enum Error: Swift.Error {
        case missingSession
        case missingSessionMessages
    }
}
