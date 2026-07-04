import Foundation
import SQLite3

public final class SQLiteStore {
    private var db: OpaquePointer?

    // Fractional seconds so unlocks recorded close together still sort by real
    // time; `rowid` in allUnlocks breaks any remaining ties deterministically.
    // Instance-scoped because the store is used serially by a single owner.
    private let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoPlain = ISO8601DateFormatter()

    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            // sqlite3_open may allocate a handle even on failure; release it.
            sqlite3_close(db)
            db = nil
            throw StoreError.openFailed
        }
        do {
            try migrate()
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
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
        (achievement_id, scope_key, name, project_key, thread_id, unlocked_at, trigger_summary)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [unlock.achievementID, unlock.scopeKey, unlock.name, unlock.projectKey ?? "", unlock.threadID ?? "", iso(unlock.unlockedAt), unlock.triggerSummary])
    }

    public func unlockCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM achievement_unlocks;")
    }

    public func allUnlocks() throws -> [AchievementUnlock] {
        let sql = """
        SELECT achievement_id, scope_key, name, project_key, thread_id, unlocked_at, trigger_summary
        FROM achievement_unlocks
        ORDER BY unlocked_at DESC, rowid DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var unlocks: [AchievementUnlock] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let achievementID = columnString(statement, 0)
            let scopeKey = columnString(statement, 1)
            let name = columnString(statement, 2)
            let projectKey = columnString(statement, 3)
            let threadID = columnString(statement, 4)
            let unlockedAt = parseISO(columnString(statement, 5)) ?? .distantPast
            let triggerSummary = columnString(statement, 6)
            unlocks.append(AchievementUnlock(
                achievementID: achievementID,
                name: name,
                projectKey: projectKey.isEmpty ? nil : projectKey,
                threadID: threadID.isEmpty ? nil : threadID,
                scopeKey: scopeKey,
                unlockedAt: unlockedAt,
                triggerSummary: triggerSummary
            ))
        }
        return unlocks
    }

    /// Persisted per-file fingerprints (path -> fingerprint) so that only new or
    /// changed transcripts are re-parsed across app launches.
    public func knownFileFingerprints() throws -> [String: String] {
        var statement: OpaquePointer?
        let sql = "SELECT path, fingerprint FROM source_files;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var fingerprints: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            fingerprints[columnString(statement, 0)] = columnString(statement, 1)
        }
        return fingerprints
    }

    public func recordFileFingerprint(path: String, fingerprint: String) throws {
        try execute(
            "INSERT OR REPLACE INTO source_files (path, fingerprint) VALUES (?, ?);",
            [path, fingerprint]
        )
    }

    /// Identities of unlocks already recorded, so re-indexing does not re-emit
    /// or re-notify them. Keys match `AchievementUnlock.unlockKey`.
    public func existingUnlockKeys() throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "SELECT achievement_id, scope_key FROM achievement_unlocks;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var keys: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let achievementID = columnString(statement, 0)
            let scopeKey = columnString(statement, 1)
            keys.insert(makeUnlockKey(achievementID: achievementID, scopeKey: scopeKey))
        }
        return keys
    }

    private func migrate() throws {
        // The unlock table's identity changed from (achievement_id, project_key)
        // to a cooldown-derived scope. An older database lacks scope_key and has
        // the wrong primary key, so recreate it and clear file fingerprints to
        // force a full re-index that repopulates unlocks correctly.
        let unlockColumns = try columnNames(of: "achievement_unlocks")
        if !unlockColumns.isEmpty, !unlockColumns.contains("scope_key") {
            try execute("DROP TABLE achievement_unlocks;", [])
            try execute("DROP TABLE IF EXISTS source_files;", [])
        }

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
            scope_key TEXT NOT NULL,
            name TEXT NOT NULL,
            project_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            unlocked_at TEXT NOT NULL,
            trigger_summary TEXT NOT NULL,
            PRIMARY KEY (achievement_id, scope_key)
        );
        """, [])
        try execute("""
        CREATE TABLE IF NOT EXISTS source_files (
            path TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL
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
        return isoFractional.string(from: date)
    }

    private func parseISO(_ value: String) -> Date? {
        // Tolerate both formats so timestamps written before this change (plain,
        // second-resolution) still read back correctly.
        isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    /// Column names of a table, or an empty set if it does not exist.
    private func columnNames(of table: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            names.insert(columnString(statement, 1)) // PRAGMA table_info: column 1 is name
        }
        return names
    }

    public enum StoreError: Error {
        case openFailed
        case prepareFailed
        case stepFailed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
