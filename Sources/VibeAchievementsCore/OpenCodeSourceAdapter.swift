import Foundation
import CryptoKit

enum OpenCodeSourceIdentity {
    static let sourceTool: SourceTool = .openCode
}

enum OpenCodeGeneration: String, Comparable, Sendable {
    case current
    case compatibility
    case legacy

    static func < (lhs: OpenCodeGeneration, rhs: OpenCodeGeneration) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .current: return 0
        case .compatibility: return 1
        case .legacy: return 2
        }
    }
}

enum OpenCodeRecordID {
    private static let separator = "\u{1F}"

    static func database(databaseURL: URL, generation: OpenCodeGeneration, sessionID: String) -> String {
        "db:\(databaseURL.standardizedFileURL.path)|\(generation.rawValue)|\(sessionID)"
    }

    static func locator(generation: OpenCodeGeneration, sessionID: String) -> String {
        "\(generation.rawValue)\(separator)\(sessionID)"
    }

    static func decodeDatabase(_ value: String) -> (generation: OpenCodeGeneration, sessionID: String)? {
        let components = value.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2,
              let generation = OpenCodeGeneration(rawValue: String(components[0])) else {
            return nil
        }
        return (generation, String(components[1]))
    }

    static func legacy(projectID: String, sessionID: String) -> String {
        "legacy|\(projectID)|\(sessionID)"
    }

    static func decodeLegacy(_ value: String) -> (projectID: String, sessionID: String)? {
        let components = value.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "legacy" else { return nil }
        return (String(components[1]), String(components[2]))
    }
}

struct OpenCodeMessageDraft {
    let id: String
    let role: MessageRole
    let timestamp: Date?
    let text: String
    let rawType: String
    let tokenCount: Int
}

enum OpenCodeSupport {
    static func value(_ row: [String?], at index: Int) -> String? {
        guard row.indices.contains(index) else { return nil }
        return row[index]
    }

    static func jsonObject(_ value: String?) -> [String: Any]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func jsonObject(data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func integer(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? NSNumber { return value.intValue }
            if let value = object[key] as? String, let integer = Int(value) { return integer }
        }
        return nil
    }

    static func date(milliseconds value: String?) -> Date? {
        guard let value, let milliseconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    static func date(_ object: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue / 1_000)
            }
            if let value = object[key] as? Double {
                return Date(timeIntervalSince1970: value / 1_000)
            }
            if let value = object[key] as? String, let milliseconds = Double(value) {
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
        }
        return nil
    }

    static func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    static func role(from value: String?) -> MessageRole? {
        switch value?.lowercased() {
        case "user", "human": return .user
        case "assistant", "agent": return .assistant
        default: return nil
        }
    }

    static func text(from value: Any?) -> String {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] {
            if let text = object["text"] as? String { return text }
            return text(from: object["content"])
        }
        return TextContent.extract(from: value)
    }

    static func tokenCount(from value: Any?) -> Int {
        guard let object = value as? [String: Any] else { return 0 }
        if let total = object["total_token_usage"] as? [String: Any] {
            return tokenCount(from: total)
        }

        let keys = [
            "input", "output", "input_tokens", "output_tokens",
            "cache_read", "cache_read_input_tokens",
            "cache_creation", "cache_creation_input_tokens",
            "reasoning", "reasoning_tokens"
        ]
        return keys.reduce(0) { total, key in
            if let number = object[key] as? NSNumber { return total + number.intValue }
            if let string = object[key] as? String, let number = Int(string) { return total + number }
            return total
        }
    }

    static func tokens(from object: [String: Any]) -> Int {
        for key in ["tokens", "usage", "tokenUsage", "token_usage"] {
            if let value = object[key] {
                let count = tokenCount(from: value)
                if count > 0 { return count }
            }
        }
        return 0
    }

    static func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    static func transcript(
        sessionID: String,
        sourcePath: String,
        projectPath: String?,
        title: String?,
        createdAt: Date?,
        updatedAt: Date?,
        drafts: [OpenCodeMessageDraft],
        rawTokenCount: Int?
    ) -> ParsedTranscript {
        let threadID = "opencode:\(sessionID)"
        let messages = drafts.map { draft in
            NormalizedMessage(
                id: draft.id,
                threadID: threadID,
                sourceTool: OpenCodeSourceIdentity.sourceTool,
                sourceMessageID: draft.id,
                role: draft.role,
                timestamp: draft.timestamp,
                text: draft.text,
                rawType: draft.rawType
            )
        }
        let messageCreatedAt = drafts.reduce(createdAt) { OpenCodeSupport.minDate($0, $1.timestamp) }
        let messageUpdatedAt = drafts.reduce(updatedAt) { OpenCodeSupport.maxDate($0, $1.timestamp) }
        let thread = NormalizedThread(
            id: threadID,
            sourceTool: OpenCodeSourceIdentity.sourceTool,
            sourceThreadID: sessionID,
            sourcePath: sourcePath,
            projectPath: projectPath,
            projectKey: projectKey(for: projectPath),
            title: title,
            createdAt: messageCreatedAt,
            updatedAt: messageUpdatedAt,
            messageCount: messages.count,
            userTurnCount: messages.filter { $0.role == .user }.count,
            assistantTurnCount: messages.filter { $0.role == .assistant }.count,
            estimatedTokens: messages.reduce(0) { $0 + $1.estimatedTokens },
            rawTokenCount: rawTokenCount
        )
        return ParsedTranscript(thread: thread, messages: messages)
    }

    static func normalizedDigest(_ transcript: ParsedTranscript) -> String {
        let value = transcript.messages
            .map { "\($0.role.rawValue)\u{1F}\($0.text)" }
            .joined(separator: "\u{1E}")
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct OpenCodeSourceAdapter: ConversationSourceAdapter {
    public let sourceTool: SourceTool = OpenCodeSourceIdentity.sourceTool
    public let displayName = "OpenCode"

    private let dataRoot: URL
    private let environment: [String: String]
    private let detectorVersion: String

    public init(
        dataRoot: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        detectorVersion: String = "opencode-v1"
    ) {
        self.environment = environment
        self.detectorVersion = detectorVersion
        if let dataRoot {
            self.dataRoot = dataRoot
        } else if let xdg = environment["XDG_DATA_HOME"] {
            self.dataRoot = URL(fileURLWithPath: xdg).appendingPathComponent("opencode", isDirectory: true)
        } else {
            self.dataRoot = home.appendingPathComponent(".local/share/opencode", isDirectory: true)
        }
    }

    public func discover() throws -> SourceInventory {
        guard isDirectory(dataRoot) else {
            throw SourceDiscoveryError.unavailable(path: dataRoot.path)
        }

        var warnings: [SourceWarning] = []
        var records: [ConversationSourceRecord] = []
        var sqliteSessionIDs = Set<String>()
        var databaseRecords: [ConversationSourceRecord] = []

        for databaseURL in databaseURLs() {
            do {
                let result = try discoverDatabase(at: databaseURL)
                databaseRecords.append(contentsOf: result.records)
                sqliteSessionIDs.formUnion(result.sessionIDs)
                warnings.append(contentsOf: result.warnings)
            } catch {
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: databaseURL.path,
                    code: error is ReadOnlySQLiteSnapshot.Error ? .sourceBusy : .schemaUnsupported,
                    message: "Could not inspect \(databaseURL.path): \(error)"
                ))
            }
        }

        records.append(contentsOf: selectPreferredDatabaseRecords(databaseRecords, warnings: &warnings))

        let storageRoot = dataRoot.appendingPathComponent("storage", isDirectory: true)
        if isDirectory(storageRoot) {
            do {
                let legacyRecords = try discoverLegacyRecords(
                    storageRoot: storageRoot,
                    excludedSessionIDs: sqliteSessionIDs
                )
                records.append(contentsOf: legacyRecords)
            } catch {
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: storageRoot.path,
                    code: .malformedRecord,
                    message: "Could not inspect legacy storage: \(error)"
                ))
            }
        }

        return SourceInventory(
            records: records.sorted { $0.stableID < $1.stableID },
            warnings: warnings,
            detectedRoots: [dataRoot] + (isDirectory(storageRoot) ? [storageRoot] : [])
        )
    }

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == sourceTool else {
            throw ConversationSourceAdapterError.invalidRecord
        }

        switch record.locator {
        case let .database(database, recordID):
            guard let decoded = OpenCodeRecordID.decodeDatabase(recordID) else {
                throw ConversationSourceAdapterError.invalidRecord
            }
            switch decoded.generation {
            case .current:
                return try OpenCodeCurrentStoreReader().parse(databaseURL: database, sessionID: decoded.sessionID)
            case .compatibility:
                return try OpenCodeCompatibilityStoreReader().parse(databaseURL: database, sessionID: decoded.sessionID)
            case .legacy:
                throw ConversationSourceAdapterError.invalidRecord
            }
        case let .directory(root, recordID):
            guard let decoded = OpenCodeRecordID.decodeLegacy(recordID) else {
                throw ConversationSourceAdapterError.invalidRecord
            }
            return try OpenCodeLegacyStoreReader().parse(
                storageRoot: root,
                projectID: decoded.projectID,
                sessionID: decoded.sessionID
            )
        case .file:
            throw ConversationSourceAdapterError.invalidRecord
        }
    }

    private struct DatabaseDiscoveryResult {
        let records: [ConversationSourceRecord]
        let sessionIDs: Set<String>
        let warnings: [SourceWarning]
    }

    private func databaseURLs() -> [URL] {
        var urls: [URL] = []
        if let override = environment["OPENCODE_DB"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, relativeTo: dataRoot).standardizedFileURL
            urls.append(url)
        }
        urls.append(dataRoot.appendingPathComponent("opencode.db"))
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dataRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            urls.append(contentsOf: entries.filter { url in
                url.lastPathComponent.hasPrefix("opencode-")
                    && url.pathExtension == "db"
                    && isRegularFile(url)
            }.sorted { $0.path < $1.path })
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted && isRegularFile($0) }
    }

    private func discoverDatabase(at databaseURL: URL) throws -> DatabaseDiscoveryResult {
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: databaseURL)
        let result = try snapshot.withReadTransaction { transaction -> DatabaseDiscoveryResult in
            let tables = try Set(transaction.stringRows(
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('session', 'session_message', 'message', 'part', 'project', 'project_directory');"
            ).compactMap { $0.first })
            guard tables.contains("session") else { throw AdapterError.unsupportedSchema }

            let sessionRows = try transaction.stringRows(
                sql: "SELECT id, time_created, time_updated FROM session ORDER BY id;"
            )
            let currentIDs = tables.contains("session_message")
                ? Set(try transaction.stringRows(sql: "SELECT DISTINCT session_id FROM session_message WHERE session_id IS NOT NULL ORDER BY session_id;").compactMap { $0.first })
                : []
            let compatibilityIDs = tables.contains("message") && tables.contains("part")
                ? Set(try transaction.stringRows(sql: "SELECT DISTINCT session_id FROM message WHERE session_id IS NOT NULL ORDER BY session_id;").compactMap { $0.first })
                : []
            guard !currentIDs.isEmpty || !compatibilityIDs.isEmpty else {
                throw AdapterError.unsupportedSchema
            }

            var records: [ConversationSourceRecord] = []
            var sessionIDs = Set<String>()
            for row in sessionRows {
                guard let sessionID = row.first ?? nil, !sessionID.isEmpty else { continue }
                let generation: OpenCodeGeneration?
                if currentIDs.contains(sessionID) {
                    generation = .current
                } else if compatibilityIDs.contains(sessionID) {
                    generation = .compatibility
                } else {
                    generation = nil
                }
                guard let generation else { continue }
                let fingerprint = try fingerprint(
                    transaction: transaction,
                    databaseURL: databaseURL,
                    sessionID: sessionID,
                    generation: generation,
                    sessionRow: row
                )
                let locatorID = OpenCodeRecordID.locator(generation: generation, sessionID: sessionID)
                records.append(ConversationSourceRecord(
                    sourceTool: sourceTool,
                    stableID: OpenCodeRecordID.database(databaseURL: databaseURL, generation: generation, sessionID: sessionID),
                    displayPath: databaseURL.path,
                    locator: .database(database: databaseURL, recordID: locatorID),
                    fingerprint: fingerprint
                ))
                sessionIDs.insert(sessionID)
            }

            return DatabaseDiscoveryResult(records: records, sessionIDs: sessionIDs, warnings: [])
        }
        return result
    }

    private func fingerprint(
        transaction: ReadOnlySQLiteSnapshot.ReadTransaction,
        databaseURL: URL,
        sessionID: String,
        generation: OpenCodeGeneration,
        sessionRow: [String?]
    ) throws -> String {
        let sessionMetadata = sessionRow.dropFirst().compactMap { $0 }.joined(separator: ":")
        let aggregate: [String?]
        switch generation {
        case .current:
            aggregate = try transaction.stringRows(sql: "SELECT COUNT(*), COALESCE(MAX(seq), ''), COALESCE(MAX(time_updated), '') FROM session_message WHERE session_id = \(OpenCodeSupport.sqlQuote(sessionID));").first ?? []
        case .compatibility:
            aggregate = try transaction.stringRows(sql: "SELECT COUNT(DISTINCT m.id), COALESCE(MAX(m.time_updated), ''), COUNT(p.id) FROM message m LEFT JOIN part p ON p.message_id = m.id WHERE m.session_id = \(OpenCodeSupport.sqlQuote(sessionID));").first ?? []
        case .legacy:
            aggregate = []
        }
        return "\(detectorVersion)-\(generation.rawValue)-\(databaseURL.path)-\(sessionID)-\(sessionMetadata)-\(aggregate.compactMap { $0 }.joined(separator: ":"))"
    }

    private func discoverLegacyRecords(storageRoot: URL, excludedSessionIDs: Set<String>) throws -> [ConversationSourceRecord] {
        let sessionRoot = storageRoot.appendingPathComponent("session", isDirectory: true)
        guard isDirectory(sessionRoot) else { return [] }
        let projects = try FileManager.default.contentsOfDirectory(
            at: sessionRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { isDirectory($0) }.sorted { $0.path < $1.path }

        var records: [ConversationSourceRecord] = []
        for projectURL in projects {
            let projectID = projectURL.lastPathComponent
            let sessions = try FileManager.default.contentsOfDirectory(
                at: projectURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" && isRegularFile($0) }.sorted { $0.path < $1.path }
            for sessionURL in sessions {
                let sessionID = sessionURL.deletingPathExtension().lastPathComponent
                guard !excludedSessionIDs.contains(sessionID) else { continue }
                let fingerprint = try OpenCodeLegacyStoreReader().fingerprint(
                    storageRoot: storageRoot,
                    projectID: projectID,
                    sessionID: sessionID,
                    detectorVersion: detectorVersion
                )
                records.append(ConversationSourceRecord(
                    sourceTool: sourceTool,
                    stableID: OpenCodeRecordID.legacy(projectID: projectID, sessionID: sessionID),
                    displayPath: sessionURL.path,
                    locator: .directory(root: storageRoot, recordID: OpenCodeRecordID.legacy(projectID: projectID, sessionID: sessionID)),
                    fingerprint: fingerprint
                ))
            }
        }
        return records
    }

    private func selectPreferredDatabaseRecords(
        _ records: [ConversationSourceRecord],
        warnings: inout [SourceWarning]
    ) -> [ConversationSourceRecord] {
        let grouped = Dictionary(grouping: records) { record -> String in
            guard case let .database(_, recordID) = record.locator,
                  let decoded = OpenCodeRecordID.decodeDatabase(recordID) else { return record.stableID }
            return decoded.sessionID
        }
        var selected: [ConversationSourceRecord] = []
        for sessionRecords in grouped.values {
            guard let preferredGeneration = sessionRecords.compactMap({ record -> OpenCodeGeneration? in
                guard case let .database(_, recordID) = record.locator else { return nil }
                return OpenCodeRecordID.decodeDatabase(recordID)?.generation
            }).min() else {
                selected.append(contentsOf: sessionRecords)
                continue
            }
            let preferred = sessionRecords.filter { record in
                guard case let .database(_, recordID) = record.locator,
                      let decoded = OpenCodeRecordID.decodeDatabase(recordID) else { return false }
                return decoded.generation == preferredGeneration
            }.sorted { $0.displayPath < $1.displayPath }

            guard preferred.count > 1 else {
                selected.append(contentsOf: preferred)
                continue
            }

            var digestToRecord: [String: ConversationSourceRecord] = [:]
            for record in preferred {
                do {
                    let parsed = try parse(record)
                    let digest = OpenCodeSupport.normalizedDigest(parsed)
                    if digestToRecord[digest] == nil {
                        digestToRecord[digest] = record
                    } else {
                        warnings.append(SourceWarning(
                            sourceTool: sourceTool,
                            recordID: record.stableID,
                            code: .duplicateRecord,
                            message: "Ignored duplicate OpenCode session content from \(record.displayPath)"
                        ))
                    }
                } catch {
                    selected.append(record)
                }
            }
            selected.append(contentsOf: digestToRecord.values)
        }
        return selected
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private enum AdapterError: Error {
        case unsupportedSchema
    }
}
