import Foundation

/// A transcript that could not be parsed during indexing. Surfaced instead of
/// being silently dropped, so a source that fails to parse is diagnosable.
public struct IndexWarning: Sendable, Equatable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Outcome of an indexing pass: the achievements unlocked plus any files that
/// were skipped because they could not be parsed.
public struct IndexResult: Sendable {
    public var unlocks: [AchievementUnlock]
    public var warnings: [IndexWarning]

    public init(unlocks: [AchievementUnlock], warnings: [IndexWarning]) {
        self.unlocks = unlocks
        self.warnings = warnings
    }
}

public enum Indexer {
    @discardableResult
    public static func index(
        adapters: [any ConversationSourceAdapter],
        contracts: [AchievementContract],
        store: SQLiteStore,
        scanID: String
    ) throws -> IndexResult {
        var unlockedIDs = try store.unlockedAchievementIDs()
        var allUnlocks: [AchievementUnlock] = []
        var warnings: [IndexWarning] = []

        for adapter in adapters {
            let inventory: SourceInventory
            do {
                inventory = try adapter.discover()
            } catch {
                warnings.append(IndexWarning(path: adapter.displayName, message: String(describing: error)))
                continue
            }

            warnings.append(contentsOf: inventory.warnings.map { warning in
                let path = inventory.records.first { $0.stableID == warning.recordID }?.displayPath
                    ?? warning.recordID
                    ?? adapter.displayName
                return IndexWarning(path: path, message: warning.message)
            })

            var seenRecordIDs = Set<String>()
            for record in inventory.records {
                guard record.sourceTool == adapter.sourceTool else {
                    warnings.append(IndexWarning(
                        path: record.displayPath,
                        message: "Adapter returned a record for \(record.sourceTool.rawValue)"
                    ))
                    continue
                }
                guard seenRecordIDs.insert(record.stableID).inserted else {
                    warnings.append(IndexWarning(path: record.displayPath, message: "Duplicate source record identity"))
                    continue
                }

                let knownRecord = try store.sourceRecord(identity: record.identity)
                if knownRecord != nil {
                    try store.markSourceRecordSeen(
                        identity: record.identity,
                        displayPath: record.displayPath,
                        scanID: scanID
                    )
                }
                let hasCompleteUnchangedState = knownRecord?.fingerprint == record.fingerprint
                    && !(knownRecord?.threadID.isEmpty ?? true)
                guard !hasCompleteUnchangedState else { continue }

                let parsed: ParsedTranscript
                do {
                    parsed = try adapter.parse(record)
                } catch {
                    warnings.append(IndexWarning(path: record.displayPath, message: String(describing: error)))
                    continue
                }

                try store.upsert(thread: parsed.thread)
                let remainingContracts = contracts.filter {
                    $0.active && $0.status == "keep" && !unlockedIDs.contains($0.id)
                }
                let events = EventExtractor.extract(from: parsed)
                let unlocks = AchievementEngine.evaluate(
                    contracts: remainingContracts,
                    parsed: parsed,
                    events: events,
                    existingUnlockedIDs: unlockedIDs
                )
                for unlock in unlocks {
                    try store.insert(unlock: unlock)
                    unlockedIDs.insert(unlock.achievementID)
                }
                allUnlocks.append(contentsOf: unlocks)
                try store.recordSourceRecord(
                    record: record,
                    threadID: parsed.thread.id,
                    scanID: scanID
                )
            }

            try store.reconcileMissingSourceRecords(
                sourceTool: adapter.sourceTool,
                seenRecordIDs: seenRecordIDs,
                scanID: scanID
            )
        }

        return IndexResult(unlocks: allUnlocks, warnings: warnings)
    }

    @discardableResult
    public static func index(paths: [URL], contractsURL: URL, storePath: String) throws -> IndexResult {
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
        return try index(paths: paths, contracts: contracts, storePath: storePath)
    }

    @discardableResult
    public static func index(paths: [URL], contracts: [AchievementContract], storePath: String) throws -> IndexResult {
        let store = try SQLiteStore(path: storePath)
        return try index(paths: paths, contracts: contracts, store: store)
    }

    @discardableResult
    public static func index(paths: [URL], contracts: [AchievementContract], store: SQLiteStore) throws -> IndexResult {
        var unlockedIDs = try store.unlockedAchievementIDs()
        var allUnlocks: [AchievementUnlock] = []
        var warnings: [IndexWarning] = []

        for path in paths where path.pathExtension == "jsonl" {
            let remainingContracts = contracts.filter { $0.active && $0.status == "keep" && !unlockedIDs.contains($0.id) }
            guard !remainingContracts.isEmpty else { break }

            let parsed: ParsedTranscript
            do {
                parsed = try parseTranscript(at: path)
            } catch {
                // One bad file should not abort the scan, but it must not vanish
                // silently either.
                warnings.append(IndexWarning(path: path.path, message: String(describing: error)))
                continue
            }

            try store.upsert(thread: parsed.thread)
            let events = EventExtractor.extract(from: parsed)
            let unlocks = AchievementEngine.evaluate(contracts: remainingContracts, parsed: parsed, events: events, existingUnlockedIDs: unlockedIDs)
            for unlock in unlocks {
                try store.insert(unlock: unlock)
                unlockedIDs.insert(unlock.achievementID)
            }
            allUnlocks.append(contentsOf: unlocks)
        }

        return IndexResult(unlocks: allUnlocks, warnings: warnings)
    }

    private static func parseTranscript(at path: URL) throws -> ParsedTranscript {
        if path.path.contains("/.claude/projects/") {
            return try ClaudeCodeParser.parse(fileURL: path)
        }
        if path.path.contains("/.codex/") || path.lastPathComponent.hasPrefix("rollout-") {
            return try CodexParser.parse(fileURL: path)
        }
        // Sniff only the first bytes rather than reading the whole file twice.
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        let preview = String(decoding: try handle.read(upToCount: 512) ?? Data(), as: UTF8.self)
        if preview.contains("\"session_meta\"") || preview.contains("\"response_item\"") {
            return try CodexParser.parse(fileURL: path)
        }
        return try ClaudeCodeParser.parse(fileURL: path)
    }
}
