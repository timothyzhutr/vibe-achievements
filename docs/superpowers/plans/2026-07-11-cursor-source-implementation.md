# Cursor Conversation Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add read-only, incremental indexing of regular local Cursor conversations across current global storage, agent transcripts, and legacy workspace storage.

**Architecture:** `CursorSourceAdapter` probes supported generations, emits one prioritized record per conversation, and delegates parsing to focused readers. SQLite access uses the shared query-only helper; exact normalized duplicates are collapsed before indexing.

**Tech Stack:** Swift 6, Foundation JSON, SQLite3, CryptoKit SHA-256, XCTest.

## Implementation Status

Implemented and wired through the shared registry and Settings UI. Global
composer storage, agent transcripts, and legacy workspace storage are covered
by focused fixtures plus an incremental `Indexer` integration test. Discovery
is conservative when a configured generation is missing; cross-generation
normalized digest collapse remains a follow-up because stable Cursor IDs differ
between storage generations.

---

**Dependency:** Complete `2026-07-11-conversation-source-adapter-implementation.md` first.

### Task 1: Discover Cursor Capabilities

**Files:**
- Create: `Sources/VibeAchievementsCore/CursorSourceAdapter.swift`
- Create: `Tests/VibeAchievementsCoreTests/CursorSourceAdapterTests.swift`

- [ ] Write failing tests for global DB, workspace DB plus `workspace.json`, transcript roots, missing roots, and allowlisted schema rejection.
- [ ] Run `swift test --filter CursorSourceAdapterTests`; expect missing adapter failures.
- [ ] Implement default roots, SQLite table/column probes, exact KV-prefix allowlists, and transcript enumeration. Never enumerate AI tracking, checkpoints, context, secrets, or logs.

```swift
static func defaultRoots(home: URL) -> CursorRoots {
    CursorRoots(
        applicationSupport: home.appendingPathComponent("Library/Application Support/Cursor"),
        projects: home.appendingPathComponent(".cursor/projects")
    )
}
let allowedPrefixes = ["composerData:", "bubbleId:", "agentKv:blob:"]
```
- [ ] Fingerprint global composers from `lastUpdatedAt` and ordered bubble/blob IDs; fingerprint transcripts from size/mtime; fingerprint legacy composers from workspace/composer/update metadata.
- [ ] Run `swift test --filter CursorSourceAdapterTests`; expect PASS.
- [ ] Commit with `git commit -m "Discover supported Cursor conversation stores"`.

### Task 2: Parse Global Cursor Composer Storage

**Files:**
- Create: `Sources/VibeAchievementsCore/CursorGlobalStoreReader.swift`
- Create: `Tests/VibeAchievementsCoreTests/CursorGlobalStoreReaderTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/cursor-global-composer.json`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/cursor-global-bubbles.jsonl`

- [ ] Write failing fixture tests for composer identity, `fullConversationHeadersOnly` order, human/assistant roles, `text`/`rawText` fallback, ISO and epoch timestamps, missing blobs, and workspace URI project identity.
- [ ] Run `swift test --filter CursorGlobalStoreReaderTests`; expect missing reader failures.
- [ ] Query only `composerData:<id>`, ordered `bubbleId:<composer>:<bubble>`, and referenced `agentKv:blob:<hash>` rows. Decode JSON by field presence and ignore unknown fields.

```sql
SELECT key, value FROM cursorDiskKV
WHERE key = ? OR key = ?;
```

Bind exact composer/bubble/blob keys; never execute a prefix-wide value dump.
- [ ] Normalize IDs as `cursor:<workspaceIdentity>:<composerId>` and bubble IDs as source message IDs. Missing bubble/blob yields one warning and does not drop valid messages.
- [ ] Run focused tests; expect PASS.
- [ ] Commit with `git commit -m "Parse global Cursor composer storage"`.

### Task 3: Parse Transcript And Legacy Generations

**Files:**
- Create: `Sources/VibeAchievementsCore/CursorTranscriptParser.swift`
- Create: `Sources/VibeAchievementsCore/CursorLegacyStoreReader.swift`
- Create: `Tests/VibeAchievementsCoreTests/CursorTranscriptParserTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/CursorLegacyStoreReaderTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/cursor-agent-transcript.jsonl`

- [ ] Write failing tests for transcript line order, role/content extraction, ignored `turn_ended`, nil message timestamps, legacy `composer.composerData`, and `workspace.json` folder/workspace identity.
- [ ] Run both focused test suites; expect missing parser failures.
- [ ] Parse transcript `message.content` text items and supported roles. Parse legacy composer headers/bubbles through exact workspace DB keys.

```swift
struct CursorTranscriptRow: Decodable {
    var role: String?
    var message: CursorTranscriptMessage?
    var type: String?
}
```
- [ ] Add generation priority `global KV -> transcript -> legacy` per conversation ID. Collapse cross-generation exact role/text digests with CryptoKit SHA-256.
- [ ] Run all Cursor parser tests; expect equivalent normalized fixtures and one selected representation.
- [ ] Commit with `git commit -m "Support Cursor transcript and legacy history"`.

### Task 4: Add Settings And Real Local Validation

**Files:**
- Modify: `Sources/VibeAchievementsCore/Models.swift`
- Modify: `Sources/VibeAchievementsCore/ConversationSourceRegistry.swift`
- Modify: `Sources/vibe-achievements-app/AppSourceSettings.swift`
- Modify: `Sources/vibe-achievements-app/SettingsView.swift`
- Modify: `Tests/VibeAchievementsAppTests/AppSourceSettingsTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/CursorIntegrationTests.swift`

- [ ] Write failing tests for `.cursor`, enabled/default/manual settings, registry inclusion, duplicate suppression, and unchanged-rescan zero parse calls.
- [ ] Add `SourceTool.cursor`, default `~/Library/Application Support/Cursor`, and one Cursor settings row.

```swift
var cursorEnabled = true
var cursorHomePath: String?
```
- [ ] Run synthetic integration tests, then run a read-only local smoke command that reports only conversation counts, role counts, and project-known counts. Assert no fixture/log contains real text.
- [ ] Run `swift test && Scripts/make-dmg.sh && git diff --check`; expect success.
- [ ] Commit with `git commit -m "Wire Cursor conversation history source"`.
