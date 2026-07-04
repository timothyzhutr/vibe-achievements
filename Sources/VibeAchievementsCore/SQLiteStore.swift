import Foundation
import SQLite3

public final class SQLiteStore {
    private var db: OpaquePointer?

    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.openFailed
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func upsert(thread: NormalizedThread) throws {
        let sql = """
        INSERT OR REPLACE INTO threads
        (id, source_tool, source_thread_id, source_path, project_path, project_key, title, created_at, updated_at, message_count, user_turn_count, assistant_turn_count, estimated_tokens, raw_token_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [
            thread.id, thread.sourceTool.rawValue, thread.sourceThreadID, thread.sourcePath, thread.projectPath ?? "", thread.projectKey, thread.title ?? "",
            iso(thread.createdAt), iso(thread.updatedAt), thread.messageCount, thread.userTurnCount, thread.assistantTurnCount, thread.estimatedTokens, thread.rawTokenCount ?? 0
        ])
    }

    public func insert(unlock: AchievementUnlock) throws {
        let sql = """
        INSERT OR IGNORE INTO achievement_unlocks
        (achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [unlock.achievementID, unlock.name, unlock.projectKey ?? "", unlock.threadID ?? "", iso(unlock.unlockedAt), unlock.triggerSummary])
    }

    public func unlockCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM achievement_unlocks;")
    }

    /// Identities of unlocks already recorded, so re-indexing does not re-emit
    /// or re-notify them. Keys match `AchievementUnlock.unlockKey`.
    public func existingUnlockKeys() throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "SELECT achievement_id, project_key FROM achievement_unlocks;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var keys: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let achievementID = String(cString: sqlite3_column_text(statement, 0))
            let projectKey = String(cString: sqlite3_column_text(statement, 1))
            keys.insert(makeUnlockKey(achievementID: achievementID, projectKey: projectKey))
        }
        return keys
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS threads (
            id TEXT PRIMARY KEY,
            source_tool TEXT NOT NULL,
            source_thread_id TEXT NOT NULL,
            source_path TEXT NOT NULL,
            project_path TEXT NOT NULL,
            project_key TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            message_count INTEGER NOT NULL,
            user_turn_count INTEGER NOT NULL,
            assistant_turn_count INTEGER NOT NULL,
            estimated_tokens INTEGER NOT NULL,
            raw_token_count INTEGER NOT NULL
        );
        """, [])
        try execute("""
        CREATE TABLE IF NOT EXISTS achievement_unlocks (
            achievement_id TEXT NOT NULL,
            name TEXT NOT NULL,
            project_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            unlocked_at TEXT NOT NULL,
            trigger_summary TEXT NOT NULL,
            PRIMARY KEY (achievement_id, project_key)
        );
        """, [])
    }

    private func execute(_ sql: String, _ values: [Any]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            if let value = value as? String {
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            } else if let value = value as? Int {
                sqlite3_bind_int(statement, position, Int32(value))
            } else {
                sqlite3_bind_null(statement, position)
            }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.stepFailed }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter().string(from: date)
    }

    public enum StoreError: Error {
        case openFailed
        case prepareFailed
        case stepFailed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
