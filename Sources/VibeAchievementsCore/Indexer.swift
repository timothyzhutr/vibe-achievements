import Foundation

public enum Indexer {
    public static func index(paths: [URL], contractsURL: URL, storePath: String) throws -> [AchievementUnlock] {
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
        return try index(paths: paths, contracts: contracts, storePath: storePath)
    }

    public static func index(paths: [URL], contracts: [AchievementContract], storePath: String) throws -> [AchievementUnlock] {
        let store = try SQLiteStore(path: storePath)
        return try index(paths: paths, contracts: contracts, store: store)
    }

    public static func index(paths: [URL], contracts: [AchievementContract], store: SQLiteStore) throws -> [AchievementUnlock] {
        var unlockedKeys = try store.existingUnlockKeys()
        var allUnlocks: [AchievementUnlock] = []

        for path in paths where path.pathExtension == "jsonl" {
            guard let parsed = try? parseTranscript(at: path) else {
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

        return allUnlocks
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
