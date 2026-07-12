# Antigravity Conversation Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add experimental read-only indexing of documented Antigravity IDE and CLI trajectory JSONL.

**Architecture:** The adapter enumerates only canonical transcript files and parses them as tolerant ordered step unions. Stable reads ignore partial final lines, unknown variants become warnings, and exact IDE/CLI duplicates collapse by normalized content digest.

**Tech Stack:** Swift 6, Foundation JSONSerialization/Codable, CryptoKit, XCTest.

## Implementation Status

Implemented and wired by default through the shared registry and Settings UI.
Canonical IDE/CLI trajectory discovery, tolerant parsing, partial-record
handling, stable-read retries, exact duplicate preference, and incremental
indexing are covered by focused fixtures and integration tests. The local brain
directories were empty, so the validation fixture is synthetic.

---

**Dependency:** Complete `2026-07-11-conversation-source-adapter-implementation.md` first.

### Task 1: Discover Canonical IDE And CLI Transcripts

**Files:**
- Create: `Sources/VibeAchievementsCore/AntigravitySourceAdapter.swift`
- Create: `Tests/VibeAchievementsCoreTests/AntigravitySourceAdapterTests.swift`

- [ ] Write failing discovery tests for both `brain` roots, UUID directories, canonical `transcript.jsonl`, excluded `transcript_full.jsonl`, empty roots, and manual root override.
- [ ] Run `swift test --filter AntigravitySourceAdapterTests`; expect missing adapter failures.
- [ ] Enumerate one directory level under `brain`, produce stable IDs `antigravity:<ide|cli>:<uuid>`, and use detector version/size/mtime fingerprints.

```swift
let roots: [(surface: String, url: URL)] = [
    ("ide", home.appendingPathComponent(".gemini/antigravity/brain")),
    ("cli", home.appendingPathComponent(".gemini/antigravity-cli/brain"))
]
let relativeTranscript = ".system_generated/logs/transcript.jsonl"
```
- [ ] Run focused tests; expect PASS.
- [ ] Commit with `git commit -m "Discover Antigravity trajectory transcripts"`.

### Task 2: Parse Tolerant Trajectory Steps

**Files:**
- Create: `Sources/VibeAchievementsCore/AntigravityParser.swift`
- Create: `Sources/VibeAchievementsCore/JSONValue.swift`
- Create: `Tests/VibeAchievementsCoreTests/AntigravityParserTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/antigravity-trajectory.jsonl`

- [ ] Create a synthetic fixture containing user input, planner response, system/ephemeral text, tool call/result, unknown variant, timestamps, workspace paths, and a partial final line. Write failing role/order/count assertions.
- [ ] Run `swift test --filter AntigravityParserTests`; expect missing parser failures.
- [ ] Decode bounded JSON values per newline-terminated line. Map recognized user/planner visible text, ignore tool records, retain nil for missing message times, and use explicit workspace/current directory for project identity.

```swift
for (ordinal, line) in completeLines.enumerated() {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    if let message = AntigravityStepDecoder.message(from: value, ordinal: ordinal) {
        messages.append(message)
    }
}
```
- [ ] Return one warning count for unknown complete variants and malformed complete lines; do not include raw content in errors.
- [ ] Run focused tests; expect valid history before the partial line and correct roles/order.
- [ ] Commit with `git commit -m "Parse Antigravity trajectory JSONL"`.

### Task 3: Handle Concurrent Writes And Exact Duplicates

**Files:**
- Modify: `Sources/VibeAchievementsCore/AntigravitySourceAdapter.swift`
- Modify: `Sources/VibeAchievementsCore/AntigravityParser.swift`
- Modify: `Tests/VibeAchievementsCoreTests/AntigravitySourceAdapterTests.swift`

- [ ] Write failing tests where size/mtime changes during read and where IDE/CLI records normalize to identical role/text sequences.
- [ ] Implement one stable-read retry and `recordChangedDuringRead` after the second change. Compute local SHA-256 over normalized role/text order and prefer IDE for exact duplicates.

```swift
func stableData(at url: URL) throws -> Data {
    for attempt in 0..<2 {
        let before = try FileStamp(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if before == (try FileStamp(url)) { return data }
        if attempt == 1 { throw SourceReadError.recordChangedDuringRead }
    }
    fatalError("unreachable")
}
```
- [ ] Prove prefix-only forks remain distinct and document this expected V1 behavior in the test name.
- [ ] Run Antigravity tests; expect PASS.
- [ ] Commit with `git commit -m "Stabilize Antigravity transcript ingestion"`.

### Task 4: Add Settings, Registry, And Validation Gate

**Files:**
- Modify: `Sources/VibeAchievementsCore/Models.swift`
- Modify: `Sources/VibeAchievementsCore/ConversationSourceRegistry.swift`
- Modify: `Sources/vibe-achievements-app/AppSourceSettings.swift`
- Modify: `Sources/vibe-achievements-app/SettingsView.swift`
- Modify: `Tests/VibeAchievementsAppTests/AppSourceSettingsTests.swift`
- Create: `Tests/VibeAchievementsCoreTests/AntigravityIntegrationTests.swift`

- [ ] Write failing tests for `.antigravity`, default/manual IDE root, CLI secondary root, registry order, and unchanged scans.
- [ ] Add settings and a source row labelled Experimental until a current real fixture passes.

```swift
var antigravityEnabled = true
var antigravityHomePath: String?
```
- [ ] Generate one local Antigravity 2.0 conversation, compare only normalized role/order/project/count metadata with the app, and sanitize its structural shapes into fixtures without retaining text.
- [ ] Run `swift test && Scripts/make-dmg.sh && git diff --check`; expect success.
- [ ] Commit with `git commit -m "Wire Antigravity conversation history source"`.
