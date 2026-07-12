# OpenCode Conversation Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add experimental read-only OpenCode indexing for current ordered SQLite, compatibility SQLite, and legacy JSON sessions.

**Architecture:** One adapter probes data roots and database capabilities, then emits one prioritized record per opaque session ID. Three focused readers normalize supported generations; SQLite uses the shared query-only helper and legacy JSON uses stable multi-file reads.

**Tech Stack:** Swift 6, Foundation JSON, SQLite3, CryptoKit, XCTest.

## Implementation Status

Implemented and wired by default through the shared registry and Settings UI.
Current ordered SQLite, compatibility SQLite, and legacy JSON storage have
focused fixtures, generation priority, duplicate handling, read retries, and an
incremental `Indexer` integration test. Real OpenCode history was not available
on this Mac, so validation remains fixture-based.

---

**Dependency:** Complete `2026-07-11-conversation-source-adapter-implementation.md` first.

### Task 1: Discover Data Roots And Session Capabilities

**Files:**
- Create: `Sources/VibeAchievementsCore/OpenCodeSourceAdapter.swift`
- Create: `Tests/VibeAchievementsCoreTests/OpenCodeSourceAdapterTests.swift`

- [ ] Write failing tests for `XDG_DATA_HOME`, default root, absolute/relative `OPENCODE_DB`, channel DBs, legacy storage, absent auth/log access, and schema capability selection.
- [ ] Run `swift test --filter OpenCodeSourceAdapterTests`; expect missing adapter failures.
- [ ] Implement strict candidates: `opencode.db`, `opencode-*.db`, and exact legacy project/session/message/part roots. Probe required tables/columns read-only.

```swift
let dataRoot = environment["XDG_DATA_HOME"]
    .map(URL.init(fileURLWithPath:))
    .map { $0.appendingPathComponent("opencode") }
    ?? home.appendingPathComponent(".local/share/opencode")
let primary = dataRoot.appendingPathComponent("opencode.db")
let legacy = dataRoot.appendingPathComponent("storage")
```
- [ ] Emit one record per database-qualified session ID and legacy session ID. Prefer current, then compatibility, then legacy for duplicate IDs.
- [ ] Run focused tests; expect PASS.
- [ ] Commit with `git commit -m "Discover OpenCode conversation stores"`.

### Task 2: Parse Current `session_message` SQLite

**Files:**
- Create: `Sources/VibeAchievementsCore/OpenCodeCurrentStoreReader.swift`
- Create: `Tests/VibeAchievementsCoreTests/OpenCodeCurrentStoreReaderTests.swift`

- [ ] Build a synthetic SQLite fixture with project, project_directory, session, and session_message rows covering user, assistant text content, system/tool types, tokens, millisecond timestamps, and out-of-time-order rows with correct `seq`. Write failing normalization assertions.
- [ ] Run focused tests; expect missing reader failures.
- [ ] Query exact columns, order by `seq`, reconstruct row-promoted `id`/`type`/timestamps before JSON decoding, concatenate assistant text items, and join project worktree/directory identity.

```sql
SELECT sm.id, sm.type, sm.seq, sm.time_created, sm.time_updated, sm.data,
       s.id, s.directory, s.title, s.time_created, s.time_updated,
       p.worktree
FROM session_message sm
JOIN session s ON s.id = sm.session_id
LEFT JOIN project p ON p.id = s.project_id
WHERE sm.session_id = ?
ORDER BY sm.seq;
```
- [ ] Use session aggregate tokens when present; otherwise sum non-cumulative assistant token structures once.
- [ ] Run focused tests; expect PASS and no token double count.
- [ ] Commit with `git commit -m "Parse current OpenCode SQLite sessions"`.

### Task 3: Parse Compatibility SQLite

**Files:**
- Create: `Sources/VibeAchievementsCore/OpenCodeCompatibilityStoreReader.swift`
- Create: `Tests/VibeAchievementsCoreTests/OpenCodeCompatibilityStoreReaderTests.swift`

- [ ] Build a synthetic compatibility DB with message/part data JSON missing promoted IDs, multiple text/tool parts, and equal timestamps. Write failing ID/order/text tests.
- [ ] Run focused tests; expect missing reader failures.
- [ ] Order messages by `time_created,id`, parts by `time_created,id`, reconstruct promoted fields, concatenate text parts only, and preserve source timestamps as supplied.

```sql
SELECT m.id, m.time_created, m.time_updated, m.data,
       p.id, p.time_created, p.time_updated, p.data
FROM message m
LEFT JOIN part p ON p.message_id = m.id
WHERE m.session_id = ?
ORDER BY m.time_created, m.id, p.time_created, p.id;
```
- [ ] Add a test proving sessions with current `session_message` rows never concatenate compatibility messages.
- [ ] Run focused tests; expect PASS.
- [ ] Commit with `git commit -m "Parse compatibility OpenCode SQLite sessions"`.

### Task 4: Parse Legacy JSON And Deduplicate Stores

**Files:**
- Create: `Sources/VibeAchievementsCore/OpenCodeLegacyStoreReader.swift`
- Create: `Tests/VibeAchievementsCoreTests/OpenCodeLegacyStoreReaderTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/opencode-legacy-session.json`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/opencode-legacy-message.json`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/opencode-legacy-part.json`

- [ ] Write failing tests for directory layout, role/text extraction, child-file ordering, project directory, read mutation retry, and exact duplicates across channel databases.
- [ ] Run focused tests; expect missing reader failures.
- [ ] Parse only referenced session/message/part JSON. Fingerprint sorted relevant child size/mtime tuples and retry once when they change.

```swift
let sessionURL = root.appendingPathComponent("session/\(projectID)/\(sessionID).json")
let messagesRoot = root.appendingPathComponent("message/\(sessionID)")
func partsRoot(messageID: String) -> URL {
    root.appendingPathComponent("part/\(messageID)")
}
```
- [ ] Collapse exact normalized role/text digests across database-qualified IDs while retaining genuinely distinct sessions.
- [ ] Run all OpenCode reader/adapter tests; expect equivalent normalization across three generations.
- [ ] Commit with `git commit -m "Support legacy OpenCode JSON history"`.

### Task 5: Add Settings And Real Installation Validation

**Files:**
- Modify: `Sources/VibeAchievementsCore/Models.swift`
- Modify: `Sources/VibeAchievementsCore/ConversationSourceRegistry.swift`
- Modify: `Sources/vibe-achievements-app/AppSourceSettings.swift`
- Modify: `Sources/vibe-achievements-app/SettingsView.swift`
- Modify: `Tests/VibeAchievementsAppTests/AppSourceSettingsTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/OpenCodeIntegrationTests.swift`

- [ ] Write failing tests for `.openCode`, default/manual data roots, registry inclusion, generation priority, source warning isolation, and unchanged rescans.
- [ ] Add settings and an Experimental source row. Manual selection points to the data root, not `opencode.db`.

```swift
var openCodeEnabled = true
var openCodeDataPath: String?
```
- [ ] Install/run OpenCode only with user approval, generate synthetic local conversations, and validate counts/order/project/tokens without logging text or opening `auth.json`.
- [ ] Run `swift test && Scripts/make-dmg.sh && git diff --check`; expect success.
- [ ] Commit with `git commit -m "Wire OpenCode conversation history source"`.
