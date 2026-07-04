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
        var unlockedKeys = try store.existingUnlockKeys()
        var allUnlocks: [AchievementUnlock] = []
        var warnings: [IndexWarning] = []

        for path in paths where path.pathExtension == "jsonl" {
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
            let unlocks = AchievementEngine.evaluate(contracts: contracts, parsed: parsed, events: events, existingUnlockKeys: unlockedKeys)
            for unlock in unlocks {
                try store.insert(unlock: unlock)
                unlockedKeys.insert(unlock.unlockKey)
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
        let data = try Data(contentsOf: path)
        let preview = String(decoding: data.prefix(512), as: UTF8.self)
        if preview.contains("\"session_meta\"") || preview.contains("\"response_item\"") {
            return try CodexParser.parse(fileURL: path)
        }
        return try ClaudeCodeParser.parse(fileURL: path)
    }
}
