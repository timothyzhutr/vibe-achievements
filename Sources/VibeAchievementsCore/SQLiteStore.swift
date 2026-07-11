import Foundation
import SQLite3

public struct SourceRecordState: Equatable, Sendable {
    public let identity: SourceRecordIdentity
    public let fingerprint: String
    public let displayPath: String
    public let threadID: String
    public let lastSeenScanID: String
    public let missingScanCount: Int
}

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
        (achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [unlock.achievementID, unlock.name, unlock.projectKey ?? "", unlock.threadID ?? "", iso(unlock.unlockedAt), unlock.triggerSummary])
    }

    public func unlockCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM achievement_unlocks;")
    }

    public func allUnlocks() throws -> [AchievementUnlock] {
        let sql = """
        SELECT achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary
        FROM achievement_unlocks
        ORDER BY unlocked_at DESC, rowid DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var unlocks: [AchievementUnlock] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let achievementID = columnString(statement, 0)
            let name = columnString(statement, 1)
            let projectKey = columnString(statement, 2)
            let threadID = columnString(statement, 3)
            let unlockedAt = parseISO(columnString(statement, 4)) ?? .distantPast
            let triggerSummary = columnString(statement, 5)
            unlocks.append(AchievementUnlock(
                achievementID: achievementID,
                name: name,
                projectKey: projectKey.isEmpty ? nil : projectKey,
                threadID: threadID.isEmpty ? nil : threadID,
                unlockedAt: unlockedAt,
                triggerSummary: triggerSummary
            ))
        }
        return unlocks
    }

    /// Unlocks that have been recorded but never notified, oldest first. Every
    /// achievement gets exactly one banner: an unlock stays here until a scan
    /// with notification permission notifies it and calls `markNotified`.
    public func unnotifiedUnlocks() throws -> [AchievementUnlock] {
        let sql = """
        SELECT achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary
        FROM achievement_unlocks
        WHERE notified_at = ''
        ORDER BY unlocked_at ASC, rowid ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var unlocks: [AchievementUnlock] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            unlocks.append(AchievementUnlock(
                achievementID: columnString(statement, 0),
                name: columnString(statement, 1),
                projectKey: columnString(statement, 2).isEmpty ? nil : columnString(statement, 2),
                threadID: columnString(statement, 3).isEmpty ? nil : columnString(statement, 3),
                unlockedAt: parseISO(columnString(statement, 4)) ?? .distantPast,
                triggerSummary: columnString(statement, 5)
            ))
        }
        return unlocks
    }

    public func markNotified(_ achievementIDs: [String], at date: Date = Date()) throws {
        guard !achievementIDs.isEmpty else { return }
        let stamp = iso(date)
        for id in achievementIDs {
            try execute("UPDATE achievement_unlocks SET notified_at = ? WHERE achievement_id = ?;", [stamp, id])
        }
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

    public func sourceRecord(identity: SourceRecordIdentity) throws -> SourceRecordState? {
        let sql = """
        SELECT fingerprint, display_path, thread_id, last_seen_scan_id, missing_scan_count
        FROM source_records
        WHERE source_tool = ? AND record_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, identity.sourceTool.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, identity.stableID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return SourceRecordState(
            identity: identity,
            fingerprint: columnString(statement, 0),
            displayPath: columnString(statement, 1),
            threadID: columnString(statement, 2),
            lastSeenScanID: columnString(statement, 3),
            missingScanCount: Int(sqlite3_column_int(statement, 4))
        )
    }

    public func recordSourceRecord(
        record: ConversationSourceRecord,
        threadID: String,
        scanID: String
    ) throws {
        try execute("""
        INSERT INTO source_records
        (source_tool, record_id, fingerprint, display_path, thread_id, last_seen_scan_id, missing_scan_count, last_missing_scan_id)
        VALUES (?, ?, ?, ?, ?, ?, 0, '')
        ON CONFLICT(source_tool, record_id) DO UPDATE SET
            fingerprint = excluded.fingerprint,
            display_path = excluded.display_path,
            thread_id = excluded.thread_id,
            last_seen_scan_id = excluded.last_seen_scan_id,
            missing_scan_count = 0,
            last_missing_scan_id = '';
        """, [
            record.sourceTool.rawValue,
            record.stableID,
            record.fingerprint,
            record.displayPath,
            threadID,
            scanID
        ])
    }

    public func markSourceRecordSeen(identity: SourceRecordIdentity, displayPath: String, scanID: String) throws {
        try execute("""
        UPDATE source_records
        SET display_path = ?, last_seen_scan_id = ?, missing_scan_count = 0, last_missing_scan_id = ''
        WHERE source_tool = ? AND record_id = ?;
        """, [displayPath, scanID, identity.sourceTool.rawValue, identity.stableID])
    }

    public func reconcileMissingSourceRecords(
        sourceTool: SourceTool,
        seenRecordIDs: Set<String>,
        scanID: String
    ) throws {
        let states = try sourceRecords(sourceTool: sourceTool)
        for state in states where !seenRecordIDs.contains(state.identity.stableID) {
            guard state.lastSeenScanID != scanID, state.lastMissingScanID != scanID else { continue }
            let nextMissingCount = state.missingScanCount + 1
            if nextMissingCount >= 2 {
                if !state.threadID.isEmpty {
                    try execute("DELETE FROM threads WHERE id = ?;", [state.threadID])
                }
                try execute(
                    "DELETE FROM source_records WHERE source_tool = ? AND record_id = ?;",
                    [sourceTool.rawValue, state.identity.stableID]
                )
            } else {
                try execute("""
                UPDATE source_records
                SET missing_scan_count = ?, last_missing_scan_id = ?
                WHERE source_tool = ? AND record_id = ?;
                """, [nextMissingCount, scanID, sourceTool.rawValue, state.identity.stableID])
            }
        }
    }

    func threadExists(id: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM threads WHERE id = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Identities of unlocks already recorded, so re-indexing does not re-emit
    /// or re-notify them. Achievement identity is global by `achievement_id`.
    public func unlockedAchievementIDs() throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "SELECT achievement_id FROM achievement_unlocks;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        var ids: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.insert(columnString(statement, 0))
        }
        return ids
    }

    private func migrate() throws {
        // Achievement identity is global by achievement_id. Older development
        // schemas keyed by project or cooldown scope, so collapse any repeats
        // into the first recorded unlock and force changed-file discovery to run
        // against the remaining locked achievement IDs.
        if try tableNeedsGlobalAchievementIdentityMigration() {
            try execute("""
            CREATE TABLE achievement_unlocks_new (
                achievement_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                project_key TEXT NOT NULL,
                thread_id TEXT NOT NULL,
                unlocked_at TEXT NOT NULL,
                trigger_summary TEXT NOT NULL
            );
            """, [])
            try execute("""
            INSERT OR IGNORE INTO achievement_unlocks_new
            (achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary)
            SELECT achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary
            FROM achievement_unlocks
            ORDER BY unlocked_at ASC, rowid ASC;
            """, [])
            try execute("DROP TABLE achievement_unlocks;", [])
            try execute("ALTER TABLE achievement_unlocks_new RENAME TO achievement_unlocks;", [])
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
            achievement_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            project_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            unlocked_at TEXT NOT NULL,
            trigger_summary TEXT NOT NULL,
            notified_at TEXT NOT NULL DEFAULT ''
        );
        """, [])
        try execute("""
        CREATE TABLE IF NOT EXISTS source_files (
            path TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL
        );
        """, [])
        try execute("""
        CREATE TABLE IF NOT EXISTS source_records (
            source_tool TEXT NOT NULL,
            record_id TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            display_path TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            last_seen_scan_id TEXT NOT NULL,
            missing_scan_count INTEGER NOT NULL DEFAULT 0,
            last_missing_scan_id TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (source_tool, record_id)
        );
        """, [])
        try migrateRecognizedSourceFiles()

        // Additive: databases created before per-unlock notification tracking
        // lack notified_at. Their existing unlocks default to unnotified and get
        // a one-time banner on the next authorized scan.
        if try !columnNames(of: "achievement_unlocks").contains("notified_at") {
            try execute("ALTER TABLE achievement_unlocks ADD COLUMN notified_at TEXT NOT NULL DEFAULT '';", [])
        }
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
                // 64-bit bind: token counts can exceed Int32.max on large
                // histories, and Int32(value) would trap.
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
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

    private func sourceRecords(sourceTool: SourceTool) throws -> [(identity: SourceRecordIdentity, threadID: String, lastSeenScanID: String, missingScanCount: Int, lastMissingScanID: String)] {
        let sql = """
        SELECT record_id, thread_id, last_seen_scan_id, missing_scan_count, last_missing_scan_id
        FROM source_records WHERE source_tool = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceTool.rawValue, -1, SQLITE_TRANSIENT)

        var records: [(SourceRecordIdentity, String, String, Int, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append((
                SourceRecordIdentity(sourceTool: sourceTool, stableID: columnString(statement, 0)),
                columnString(statement, 1),
                columnString(statement, 2),
                Int(sqlite3_column_int(statement, 3)),
                columnString(statement, 4)
            ))
        }
        return records
    }

    private func migrateRecognizedSourceFiles() throws {
        for (path, fingerprint) in try knownFileFingerprints() {
            let sourceTool: SourceTool?
            if path.contains("/.claude/projects/") {
                sourceTool = .claudeCode
            } else if path.contains("/.codex/") {
                sourceTool = .codex
            } else {
                sourceTool = nil
            }
            guard let sourceTool else { continue }
            let recordID = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            try execute("""
            INSERT OR IGNORE INTO source_records
            (source_tool, record_id, fingerprint, display_path, thread_id, last_seen_scan_id, missing_scan_count, last_missing_scan_id)
            VALUES (?, ?, ?, ?, '', 'legacy-migration', 0, '');
            """, [sourceTool.rawValue, recordID, fingerprint, path])
        }
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

    private func tableNeedsGlobalAchievementIdentityMigration() throws -> Bool {
        let columns = try columnNames(of: "achievement_unlocks")
        guard !columns.isEmpty else { return false }
        return try primaryKeyColumns(of: "achievement_unlocks") != ["achievement_id"]
    }

    private func primaryKeyColumns(of table: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var columns: [(index: Int, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = columnString(statement, 1) // PRAGMA table_info: column 1 is name
            let primaryKeyIndex = Int(sqlite3_column_int(statement, 5))
            if primaryKeyIndex > 0 {
                columns.append((primaryKeyIndex, name))
            }
        }
        return columns.sorted { $0.index < $1.index }.map(\.name)
    }

    public enum StoreError: Error {
        case openFailed
        case prepareFailed
        case stepFailed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
