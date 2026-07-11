# Conversation Source Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JSONL path sniffing with a read-only, per-conversation source adapter pipeline while preserving Claude Code and Codex behavior.

**Architecture:** Each adapter discovers stable conversation records, fingerprints them, and parses one record into `ParsedTranscript`. The shared indexer processes only changed records, persists successful fingerprints, isolates warnings by source, and evaluates achievements exactly as it does today.

**Tech Stack:** Swift 6, Foundation, SQLite3, XCTest, macOS UserDefaults.

---

### Task 1: Define Adapter And Record Types

**Files:**
- Create: `Sources/VibeAchievementsCore/ConversationSourceAdapter.swift`
- Modify: `Sources/VibeAchievementsCore/Models.swift:3`
- Create: `Tests/VibeAchievementsCoreTests/ConversationSourceAdapterTests.swift`

- [ ] **Step 1: Write the failing type/identity test**

```swift
func testRecordIdentityIncludesSourceTool() {
    let claude = ConversationSourceRecord(sourceTool: .claudeCode, stableID: "same", displayPath: "a", locator: .file(URL(fileURLWithPath: "/a")), fingerprint: "1")
    let codex = ConversationSourceRecord(sourceTool: .codex, stableID: "same", displayPath: "b", locator: .file(URL(fileURLWithPath: "/b")), fingerprint: "1")
    XCTAssertNotEqual(claude.identity, codex.identity)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ConversationSourceAdapterTests`

Expected: compilation fails because adapter types do not exist.

- [ ] **Step 3: Implement the contract**

```swift
public struct SourceRecordIdentity: Hashable, Sendable {
    public let sourceTool: SourceTool
    public let stableID: String
}

public enum SourceWarningCode: String, Sendable {
    case permissionDenied, sourceBusy, schemaUnsupported
    case malformedRecord, recordChangedDuringRead, duplicateRecord
}

public struct SourceWarning: Equatable, Sendable {
    public let sourceTool: SourceTool
    public let recordID: String?
    public let code: SourceWarningCode
    public let message: String
}

public struct SourceInventory: Sendable {
    public let records: [ConversationSourceRecord]
    public let warnings: [SourceWarning]
    public let detectedRoots: [URL]
}

public enum SourceRecordLocator: Hashable, Sendable {
    case file(URL)
    case directory(root: URL, recordID: String)
    case database(database: URL, recordID: String)
}

public struct ConversationSourceRecord: Hashable, Sendable {
    public let sourceTool: SourceTool
    public let stableID: String
    public let displayPath: String
    public let locator: SourceRecordLocator
    public let fingerprint: String
    public var identity: SourceRecordIdentity { .init(sourceTool: sourceTool, stableID: stableID) }
}

public protocol ConversationSourceAdapter: Sendable {
    var sourceTool: SourceTool { get }
    var displayName: String { get }
    func discover() throws -> SourceInventory
    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript
}
```

Change `SourceTool` conformance to
`String, Codable, CaseIterable, Hashable, Sendable` so identities and source
registries remain typed.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter ConversationSourceAdapterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore Tests/VibeAchievementsCoreTests/ConversationSourceAdapterTests.swift
git commit -m "Add conversation source adapter contract"
```

### Task 2: Add Read-Only SQLite Access

**Files:**
- Create: `Sources/VibeAchievementsCore/ReadOnlySQLiteSnapshot.swift`
- Create: `Tests/VibeAchievementsCoreTests/ReadOnlySQLiteSnapshotTests.swift`

- [ ] **Step 1: Write failing query-only and WAL tests**

```swift
func testReadsCommittedWALRowsWithoutAllowingWrites() throws {
    let source = try SQLiteFixture.walDatabase(rows: ["one", "two"])
    let reader = try ReadOnlySQLiteSnapshot(url: source)
    XCTAssertEqual(try reader.strings(sql: "SELECT value FROM allowed ORDER BY value"), ["one", "two"])
    XCTAssertThrowsError(try reader.executeForTesting("DELETE FROM allowed"))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ReadOnlySQLiteSnapshotTests`

Expected: compilation fails because the helper does not exist.

- [ ] **Step 3: Implement safe open/transaction/backup behavior**

Open with `sqlite3_open_v2(..., SQLITE_OPEN_READONLY, ...)`, execute
`PRAGMA query_only=ON`, set a 250 ms busy timeout, and wrap adapter reads in a
deferred read transaction. Add an Online Backup method that writes only to a
temporary URL owned and deleted by the helper.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter ReadOnlySQLiteSnapshotTests`

Expected: PASS for WAL visibility, denied writes, busy mapping, and cleanup.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore/ReadOnlySQLiteSnapshot.swift Tests/VibeAchievementsCoreTests/ReadOnlySQLiteSnapshotTests.swift
git commit -m "Add read-only SQLite source helper"
```

### Task 3: Wrap Claude Code And Codex

**Files:**
- Create: `Sources/VibeAchievementsCore/ClaudeCodeSourceAdapter.swift`
- Create: `Sources/VibeAchievementsCore/CodexSourceAdapter.swift`
- Modify: `Sources/VibeAchievementsCore/SourceDiscovery.swift`
- Modify: `Tests/VibeAchievementsCoreTests/SourceDiscoveryTests.swift`

- [ ] **Step 1: Write failing parity tests**

Discover fixture roots through adapters, parse every record, and assert equality
with direct `ClaudeCodeParser.parse` and `CodexParser.parse` results.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SourceDiscoveryTests`

Expected: adapter constructors are missing.

- [ ] **Step 3: Implement file adapters**

Claude stable ID is the normalized session ID from the filename; Codex stable ID
uses the rollout filename. Fingerprints use detector version, file size, and
mtime. Each adapter calls its existing parser directly, with no sniffing.

- [ ] **Step 4: Run parity tests**

Run: `swift test --filter SourceDiscoveryTests && swift test --filter ClaudeCodeParserTests && swift test --filter CodexParserTests`

Expected: PASS with unchanged normalized transcripts.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore Tests/VibeAchievementsCoreTests/SourceDiscoveryTests.swift
git commit -m "Wrap Claude and Codex in source adapters"
```

### Task 4: Migrate Incremental Indexing

**Files:**
- Modify: `Sources/VibeAchievementsCore/SQLiteStore.swift`
- Modify: `Sources/VibeAchievementsCore/Indexer.swift`
- Modify: `Tests/VibeAchievementsCoreTests/SQLiteStoreTests.swift`
- Modify: `Tests/VibeAchievementsCoreTests/IndexerTests.swift`

- [ ] **Step 1: Write failing changed/failed/removed record tests**

Use stub adapters to prove unchanged records are not parsed, failed records are
retried, one adapter failure does not block another, and a record absent for two
complete scans removes only its derived local thread.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter IndexerTests && swift test --filter SQLiteStoreTests`

Expected: path-based indexer cannot satisfy adapter tests.

- [ ] **Step 3: Add source-record persistence**

Create `source_records(source_tool,record_id,fingerprint,display_path,thread_id,last_seen_scan_id)`
with a composite primary key. Migrate recognized Claude/Codex `source_files`
paths to their real source tool; preserve unrecognized development rows until
the old table can be retired. Drop `source_files` only after all recognized rows
have matching source records.

- [ ] **Step 4: Replace `Indexer.index(paths:)` orchestration**

```swift
public static func index(adapters: [any ConversationSourceAdapter], contracts: [AchievementContract], store: SQLiteStore, scanID: String) throws -> IndexResult
```

Discover adapters independently, filter changed records through the store, parse
and persist successful records, mark seen records, and reconcile two-scan
removals. Remove `parseTranscript(at:)` path sniffing.

- [ ] **Step 5: Run and verify GREEN**

Run: `swift test --filter IndexerTests && swift test --filter SQLiteStoreTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeAchievementsCore Tests/VibeAchievementsCoreTests
git commit -m "Index incremental conversation source records"
```

### Task 5: Wire Registry And App Status

**Files:**
- Create: `Sources/VibeAchievementsCore/ConversationSourceRegistry.swift`
- Modify: `Sources/vibe-achievements-app/AppState.swift`
- Modify: `Tests/VibeAchievementsAppTests/AppStateTests.swift`

- [ ] **Step 1: Write failing registry/status tests**

Assert registry order is Claude Code then Codex and that connected, empty,
unavailable, and needs-attention inventories produce distinct summaries.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AppStateTests`

Expected: AppState still builds path arrays.

- [ ] **Step 3: Build adapters from immutable settings**

Move discovery/fingerprinting out of `AppState.performScan`; construct adapters
through the registry and call the adapter indexer. Preserve notification behavior
and five-minute scheduling.

- [ ] **Step 4: Run complete verification**

Run: `swift test && Scripts/make-dmg.sh && git diff --check`

Expected: all tests pass and app/DMG build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore Sources/vibe-achievements-app Tests
git commit -m "Wire source adapter registry into app scans"
```
