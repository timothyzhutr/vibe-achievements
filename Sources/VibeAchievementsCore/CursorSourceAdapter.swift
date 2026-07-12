import CryptoKit
import Foundation

public struct CursorRoots: Equatable, Sendable {
    public let applicationSupport: URL
    public let projects: URL

    public init(applicationSupport: URL, projects: URL) {
        self.applicationSupport = applicationSupport
        self.projects = projects
    }
}

public struct CursorSourceAdapter: ConversationSourceAdapter {
    public let sourceTool: SourceTool = .cursor
    public let displayName = "Cursor"

    private let roots: CursorRoots
    private let detectorVersion: String

    public init(roots: CursorRoots, detectorVersion: String) {
        self.roots = roots
        self.detectorVersion = detectorVersion
    }

    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CursorRoots {
        CursorRoots(
            applicationSupport: home.appendingPathComponent("Library/Application Support/Cursor"),
            projects: home.appendingPathComponent(".cursor/projects")
        )
    }

    public func discover() throws -> SourceInventory {
        var records: [ConversationSourceRecord] = []
        var warnings: [SourceWarning] = []
        var isComplete = true
        var detectedRoots: [URL] = []
        let applicationSupportExists = FileManager.default.fileExists(atPath: roots.applicationSupport.path)
        let projectsExists = FileManager.default.fileExists(atPath: roots.projects.path)

        if applicationSupportExists, isDirectory(roots.applicationSupport) {
            detectedRoots.append(roots.applicationSupport)
            let globalDatabase = roots.applicationSupport
                .appendingPathComponent("User/globalStorage/state.vscdb")
            if FileManager.default.fileExists(atPath: globalDatabase.path) {
                do {
                    records.append(contentsOf: try databaseRecords(at: globalDatabase, generation: "global"))
                } catch {
                    isComplete = false
                    warnings.append(sourceWarning(for: globalDatabase, error: error))
                }
            }

            let workspaceRoot = roots.applicationSupport.appendingPathComponent("User/workspaceStorage")
            if FileManager.default.fileExists(atPath: workspaceRoot.path) {
                detectedRoots.append(workspaceRoot)
                do {
                    let batch = try workspaceRecords(in: workspaceRoot)
                    records.append(contentsOf: batch.records)
                    warnings.append(contentsOf: batch.warnings)
                    isComplete = isComplete && batch.isComplete
                } catch {
                    isComplete = false
                    warnings.append(sourceWarning(for: workspaceRoot, error: error))
                }
            }
        } else {
            isComplete = false
            warnings.append(SourceWarning(
                sourceTool: sourceTool,
                code: .permissionDenied,
                message: "Cursor application support root is unavailable or not a directory"
            ))
        }

        if projectsExists, isDirectory(roots.projects) {
            detectedRoots.append(roots.projects)
            do {
                records.append(contentsOf: try transcriptRecords(in: roots.projects))
            } catch {
                isComplete = false
                warnings.append(sourceWarning(for: roots.projects, error: error))
            }
        } else {
            isComplete = false
            warnings.append(SourceWarning(
                sourceTool: sourceTool,
                code: .permissionDenied,
                message: "Cursor projects root is unavailable or not a directory"
            ))
        }

        return SourceInventory(
            records: deduplicated(records),
            warnings: warnings,
            detectedRoots: detectedRoots,
            isComplete: isComplete
        )
    }

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == sourceTool else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        if case let .database(_, locatorID) = record.locator {
            if locatorID.hasPrefix("legacy:") {
                return try CursorLegacyStoreReader().parse(record)
            }
            return try CursorGlobalStoreReader().parse(record)
        }
        if case let .file(url) = record.locator {
            return try CursorTranscriptParser().parse(
                fileURL: url,
                stableID: record.stableID,
                projectPath: nil
            )
        }
        throw ConversationSourceAdapterError.unsupportedRecord
    }

    private func databaseRecords(at url: URL, generation: String) throws -> [ConversationSourceRecord] {
        do {
            return try readDatabaseRecords(at: url, generation: generation, strategy: .direct)
        } catch {
            let wal = URL(fileURLWithPath: url.path + "-wal")
            let shm = URL(fileURLWithPath: url.path + "-shm")
            guard !FileManager.default.fileExists(atPath: wal.path),
                  !FileManager.default.fileExists(atPath: shm.path) else {
                throw error
            }
            return try readDatabaseRecords(at: url, generation: generation, strategy: .immutable)
        }
    }

    private func readDatabaseRecords(
        at url: URL,
        generation: String,
        strategy: ReadOnlySQLiteSnapshot.Strategy
    ) throws -> [ConversationSourceRecord] {
        let snapshot = try ReadOnlySQLiteSnapshot(sourceURL: url, strategy: strategy)
        return try snapshot.withReadTransaction { transaction in
            let rows = try transaction.stringRows(sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name IN ('composerHeaders', 'cursorDiskKV', 'ItemTable');
            """)
            let tables = Set(rows.compactMap { cell($0, 0) })
            guard tables.contains("composerHeaders") || tables.contains("cursorDiskKV") || tables.contains("ItemTable") else {
                throw CursorDiscoveryError.schemaUnsupported
            }

            var records: [ConversationSourceRecord] = []
            var keyRows: [[String?]] = []
            if tables.contains("cursorDiskKV") {
                guard try tableColumns(transaction: transaction, table: "cursorDiskKV").contains("key") else {
                    throw CursorDiscoveryError.schemaUnsupported
                }
                let valueColumn = tables.contains("composerHeaders")
                    ? "NULL"
                    : "CASE WHEN key LIKE 'composerData:%' THEN value ELSE NULL END"
                keyRows = try transaction.stringRows(sql: """
                SELECT key, \(valueColumn)
                FROM cursorDiskKV
                WHERE key LIKE 'composerData:%'
                   OR key LIKE 'bubbleId:%';
                """)
            }
            let composerIDs = Set(keyRows.compactMap { cell($0, 0) }
                .filter { $0.hasPrefix("composerData:") }
                .map { String($0.dropFirst("composerData:".count)) })
            let composerDigests = Dictionary(uniqueKeysWithValues: keyRows.compactMap { row -> (String, String)? in
                guard let key = cell(row, 0), key.hasPrefix("composerData:"),
                      let value = cell(row, 1) else { return nil }
                return (String(key.dropFirst("composerData:".count)), sha256(value))
            })
            let groupedKeys = Dictionary(grouping: keyRows.compactMap { cell($0, 0) }) { key in
                key.split(separator: ":").dropFirst().first.map(String.init) ?? ""
            }
            let bubbleCounts = groupedKeys.mapValues { $0.filter { $0.hasPrefix("bubbleId:") }.count }
            let bubbleKeys = groupedKeys.mapValues {
                $0.filter { $0.hasPrefix("bubbleId:") }.sorted().joined(separator: ",")
            }

            if tables.contains("composerHeaders") {
                let columns = try tableColumns(transaction: transaction, table: "composerHeaders")
                guard columns.contains("composerId") else { throw CursorDiscoveryError.schemaUnsupported }
                let workspaceColumn = columns.contains("workspaceId") ? "workspaceId" : "NULL"
                let createdColumn = columns.contains("createdAt") ? "createdAt" : "NULL"
                let updatedColumn = columns.contains("lastUpdatedAt") ? "lastUpdatedAt" : "NULL"
                let subagentFilter = columns.contains("isSubagent") ? "COALESCE(isSubagent, 0) = 0" : "1 = 1"
                let checkpointFilter = columns.contains("checkpointAt") ? "COALESCE(checkpointAt, 0) = 0" : "1 = 1"
                let headerRows = try transaction.stringRows(sql: "SELECT composerId, \(workspaceColumn), \(createdColumn), \(updatedColumn) FROM composerHeaders WHERE \(subagentFilter) AND \(checkpointFilter);")
                for row in headerRows {
                    guard let composerID = cell(row, 0), !composerID.isEmpty,
                          tables.contains("cursorDiskKV"), composerIDs.contains(composerID) else { continue }
                    let workspaceID = cell(row, 1).flatMap { $0.isEmpty ? nil : $0 }
                        ?? url.deletingLastPathComponent().lastPathComponent
                    let metadata = [
                        cell(row, 2) ?? "",
                        cell(row, 3) ?? "",
                        String(bubbleCounts[composerID] ?? 0),
                        bubbleKeys[composerID] ?? ""
                    ].joined(separator: ":")
                    records.append(makeDatabaseRecord(
                        database: url,
                        generation: generation,
                        workspaceID: workspaceID,
                        composerID: composerID,
                        fingerprintMetadata: metadata
                    ))
                }
            }

            if tables.contains("cursorDiskKV") && !tables.contains("composerHeaders") {
                let workspaceID = url.deletingLastPathComponent().lastPathComponent
                for composerID in composerIDs.sorted() where !composerID.isEmpty {
                    records.append(makeDatabaseRecord(
                        database: url,
                        generation: generation,
                        workspaceID: workspaceID,
                        composerID: composerID,
                        fingerprintMetadata: [
                            String(bubbleCounts[composerID] ?? 0),
                            bubbleKeys[composerID] ?? "",
                            composerDigests[composerID] ?? ""
                        ].joined(separator: ":")
                    ))
                }
            }

            if tables.contains("ItemTable") {
                let valueRows = try transaction.stringRows(
                    sql: "SELECT value FROM ItemTable WHERE key = 'composer.composerData';"
                )
                let workspaceID = url.deletingLastPathComponent().lastPathComponent
                if let value = cell(valueRows.first ?? [], 0),
                   let data = value.data(using: .utf8),
                   let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let composers = root["allComposers"] as? [[String: Any]] {
                    for composer in composers {
                        guard let composerID = composer["composerId"] as? String, !composerID.isEmpty else { continue }
                        let stableID = "cursor:\(workspaceID):\(composerID)"
                        guard !records.contains(where: { $0.stableID == stableID }) else { continue }
                        let metadata = "\(composer["createdAt"] ?? ""):\(composer["lastUpdatedAt"] ?? "")"
                        records.append(makeDatabaseRecord(
                            database: url,
                            generation: "legacy",
                            workspaceID: workspaceID,
                            composerID: composerID,
                            fingerprintMetadata: metadata
                        ))
                    }
                }
            }
            return records
        }
    }

    private func workspaceRecords(in root: URL) throws -> CursorDiscoveryBatch {
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var records: [ConversationSourceRecord] = []
        var warnings: [SourceWarning] = []
        var isComplete = true
        for candidate in directories {
            let workspace: URL
            do {
                guard try candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                workspace = candidate
            } catch {
                isComplete = false
                warnings.append(sourceWarning(for: candidate, error: error))
                continue
            }
            let database = workspace.appendingPathComponent("state.vscdb")
            guard FileManager.default.fileExists(atPath: database.path) else { continue }
            do {
                records.append(contentsOf: try databaseRecords(at: database, generation: "workspace"))
            } catch {
                isComplete = false
                warnings.append(sourceWarning(for: database, error: error))
            }
        }
        return CursorDiscoveryBatch(records: records, warnings: warnings, isComplete: isComplete)
    }

    private func transcriptRecords(in root: URL) throws -> [ConversationSourceRecord] {
        let projects = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        return try projects.flatMap { project in
            let transcriptRoot = project.appendingPathComponent("agent-transcripts")
            guard FileManager.default.fileExists(atPath: transcriptRoot.path) else {
                return [ConversationSourceRecord]()
            }
            return try SourceDiscovery.jsonlFiles(in: transcriptRoot).map { url in
                let conversationID = url.deletingPathExtension().lastPathComponent
                let stableID = "cursor:\(project.lastPathComponent):\(conversationID)"
                return ConversationSourceRecord(
                    sourceTool: sourceTool,
                    stableID: stableID,
                    displayPath: url.path,
                    locator: .file(url),
                    fingerprint: SourceFileFingerprint.make(for: url, detectorVersion: detectorVersion)
                )
            }
        }
    }

    private func makeDatabaseRecord(
        database: URL,
        generation: String,
        workspaceID: String,
        composerID: String,
        fingerprintMetadata: String
    ) -> ConversationSourceRecord {
        let stableID = "cursor:\(workspaceID):\(composerID)"
        return ConversationSourceRecord(
            sourceTool: sourceTool,
            stableID: stableID,
            displayPath: database.path,
            locator: .database(database: database, recordID: "\(generation):\(composerID)"),
            fingerprint: SourceFileFingerprint.make(
                detectorVersion: "\(detectorVersion)-\(generation)",
                components: [workspaceID, composerID, fingerprintMetadata]
            )
        )
    }

    private func deduplicated(_ records: [ConversationSourceRecord]) -> [ConversationSourceRecord] {
        var seen = Set<SourceRecordIdentity>()
        return records
            .sorted {
                let lhsPriority = generationPriority(for: $0)
                let rhsPriority = generationPriority(for: $1)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.displayPath < $1.displayPath
            }
            .filter { seen.insert($0.identity).inserted }
    }

    private func generationPriority(for record: ConversationSourceRecord) -> Int {
        guard case let .database(_, recordID) = record.locator else { return 1 }
        if recordID.hasPrefix("global:") { return 0 }
        if recordID.hasPrefix("legacy:") { return 2 }
        return 1
    }

    private func sourceWarning(for url: URL, error: Error) -> SourceWarning {
        let code: SourceWarningCode = (error as? ReadOnlySQLiteSnapshot.Error) == .busy
            ? .sourceBusy
            : .schemaUnsupported
        return SourceWarning(sourceTool: sourceTool, code: code, message: "Cursor source unavailable at \(url.path)")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private struct CursorDiscoveryBatch {
    let records: [ConversationSourceRecord]
    let warnings: [SourceWarning]
    let isComplete: Bool
}

private enum CursorDiscoveryError: Error {
    case schemaUnsupported
}

private func cell(_ row: [String?], _ index: Int) -> String? {
    guard row.indices.contains(index) else { return nil }
    return row[index]
}

private func tableColumns(
    transaction: ReadOnlySQLiteSnapshot.ReadTransaction,
    table: String
) throws -> Set<String> {
    let rows = try transaction.stringRows(sql: "PRAGMA table_info(\(table));")
    return Set(rows.compactMap { cell($0, 1) })
}

private func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}
