# Vibe Coding Achievements App Design

Date: 2026-07-04
Status: Draft for review

## Purpose

Build a lightweight macOS app that celebrates a user's AI-assisted coding journey with Steam-like achievements. The app watches local conversation history from supported AI coding tools, extracts cheap metadata and text signals, and unlocks achievements when the user's vibe coding patterns emerge.

The app is not a replacement chat client, memory system, analytics dashboard, or cloud sync layer. It is a playful local companion that makes the work of connecting conversation history across tools feel rewarding.

## Product Shape

The MVP is a **hybrid macOS menu bar app**:

- Runs quietly in the background.
- Shows a small menu bar icon.
- Uses native macOS notifications when an achievement unlocks.
- Opens a small detail view when an unlock notification is clicked.
- Provides a proper window for the achievement shelf, source settings, and basic status.

The app should feel ambient. Most user-facing achievements should be about the user's coding journey, not configuring this app.

## MVP Scope

Included:

- macOS-first app.
- Local-only processing.
- Claude Code local transcript connector.
- Codex local transcript connector.
- User-correctable watched source folders.
- Local normalized index.
- Lightweight event extraction from metadata and keyword rules.
- Achievement rule engine using `docs/achievement-trigger-contracts-v1.jsonl`.
- Native notifications for unlocks.
- Achievement shelf window.
- Settings/source status window.

Excluded from MVP:

- Cloud sync.
- Accounts.
- LLM-based classification.
- Embeddings.
- Claude Desktop / claude.ai IndexedDB parsing.
- Antigravity or other tools.
- Cross-device memory.
- A full dashboard or productivity analytics suite.

## Source Discovery

Source discovery is documented in:

- `docs/source-discovery-claude-codex.md`

Validated local MVP sources:

- Claude Code transcripts: `~/.claude/projects/**/*.jsonl`
- Codex transcripts: `$CODEX_HOME/sessions/**/*.jsonl`, defaulting to `~/.codex/sessions/**/*.jsonl`
- Codex archived transcripts: `$CODEX_HOME/archived_sessions/*.jsonl`, defaulting to `~/.codex/archived_sessions/*.jsonl`
- Codex SQLite thread metadata: `$CODEX_HOME/sqlite/state_5.sqlite`, defaulting to `~/.codex/sqlite/state_5.sqlite`

Claude Code and Codex both expose enough local information for the MVP:

- Thread/session id.
- Timestamps.
- Project working directory.
- User/assistant roles.
- Message content where plaintext is present.
- Token-ish usage signals in some cases.

## Source Connectors

### Claude Code Connector

Responsibilities:

- Discover default `~/.claude/projects` folder.
- Watch for new or changed `.jsonl` files.
- Parse each file line-by-line.
- Extract only conservative normalized fields.
- Skip malformed lines without failing the whole source.

Useful fields:

- `type`
- `timestamp`
- `sessionId`
- `uuid`
- `parentUuid`
- `cwd`
- `gitBranch`
- `message.role`
- `message.content`
- `message.usage`

Notes:

- `message.content` can be a string or array.
- Internal entry formats may change, so parsing must be defensive.

### Codex Connector

Responsibilities:

- Discover `$CODEX_HOME`, defaulting to `~/.codex`.
- Watch session and archived session JSONL folders.
- Optionally read `sqlite/state_5.sqlite` for thread metadata.
- Parse transcript JSONL line-by-line.
- Ignore encrypted content and process only plaintext fields/events.

Useful JSONL fields:

- `session_meta.payload.id`
- `session_meta.payload.cwd`
- `session_meta.payload.source`
- `session_meta.payload.model_provider`
- `response_item.payload.role`
- `response_item.payload.content`
- `event_msg.payload.type`
- `event_msg.payload.info.model_context_window`
- `event_msg.payload.info.total_token_usage`

Useful SQLite thread fields:

- `id`
- `rollout_path`
- `created_at`
- `updated_at`
- `cwd`
- `title`
- `tokens_used`
- `model`
- `preview`

## Watched Sources UX

The app attempts to auto-detect known source folders on first launch.

If sources are found:

- Start indexing.
- Show source status in the menu/window.

If sources are not found:

- The menu bar dropdown shows a quiet "No sources connected" state.
- The user can add a watched folder.

Manual import of individual conversation files is not part of the product. The user may point the app at a source folder, but after that the app watches automatically.

## Normalized Data Model

The app should normalize source-specific transcripts into a small local model.

Thread:

```text
id
source_tool
source_thread_id
source_path
project_path
project_key
title
created_at
updated_at
message_count
user_turn_count
assistant_turn_count
estimated_tokens
raw_token_count
last_indexed_at
source_fingerprint
```

Message:

```text
id
thread_id
source_tool
source_message_id
role
timestamp
text
char_count
estimated_tokens
raw_type
```

Project:

```text
id
project_key
display_path
first_seen_at
last_seen_at
source_tools_seen
active_thread_count
```

Achievement Unlock:

```text
id
achievement_id
project_key
thread_id
unlocked_at
trigger_summary
notified_at
```

Project identity should prefer explicit `cwd`. If unavailable, fall back to source path or transcript-derived project slug.

## Local Storage

Use a local SQLite database owned by the app.

SQLite is appropriate because:

- The app is local-first.
- Queries need simple counts, windows, and joins.
- It avoids building a custom file index.
- It works well for macOS background apps.

The app should store normalized metadata and extracted text needed for rules. A later privacy setting can allow users to store only derived events, but MVP may store local normalized text because keyword achievements require it.

## Event Extraction

Achievement detection should use a small event layer rather than 50 separate ad hoc scanners.

Input:

- Normalized thread metadata.
- Normalized message text.
- Source tool.
- Project identity.
- Timestamps.
- Token counts or estimates.

Output examples:

```text
coding_thread_seen
long_thread_seen
long_message_seen
correction_language_seen
context_limit_seen
token_budget_seen
stack_trace_seen
failure_seen
success_seen
verification_failure_seen
verification_success_seen
ship_language_seen
destructive_cleanup_seen
cache_ritual_seen
ui_control_seen
css_iteration_seen
tool_activity_seen
project_revisited
```

Events should include:

```text
event_type
source_tool
project_key
thread_id
message_id
timestamp
confidence
evidence_kind
```

The app should not need a model, embeddings, or semantic classifier. If a rule cannot be expressed with cheap metadata, keywords, or event sequences, the achievement should be dropped or softened.

## Achievement Rules

The achievement contract file is:

- `docs/achievement-trigger-contracts-v1.jsonl`

Each achievement contract includes:

- `id`
- `name`
- `definition`
- `detection_class`
- `signals`
- `window`
- `exclusions`
- `cooldown`
- `confidence`
- `difficulty`
- `expected_frequency`
- `active`
- `status`

Rules should be evaluated from normalized metadata and extracted events.

Current contract state:

- 46 active `keep` achievements.
- 3 dropped achievements retained in the contract for history.
- 1 future achievement for a third supported tool.

Achievement pacing matters. The app should not unlock everything during the first historical scan.

MVP pacing strategy:

- Allow a small number of starter achievements during initial backfill.
- Mark historical unlocks differently from live unlocks if needed.
- Prefer live notifications for newly observed activity after first indexing.
- Use cooldowns and difficulty tiers from the contract.

## Notification Behavior

When an achievement unlocks:

- Fire a native macOS notification.
- Include achievement name and a short unlock line.
- Clicking the notification opens an achievement detail view.
- If multiple achievements unlock during backfill, group or defer them rather than spamming notifications.

Backfill behavior:

- First scan may unlock achievements silently or show a single summary notification.
- Live unlocks after initial indexing should notify individually.

## UI

### Menu Bar Dropdown

Shows:

- Current watcher status.
- Recent unlocks.
- Connected sources.
- Pause/resume watching.
- Open achievement shelf.
- Open settings.

### Achievement Shelf

Shows:

- All active achievements.
- Locked/unlocked state.
- Unlock date for completed achievements.
- Difficulty tier.
- Category.
- Search/filter by category or status.

### Settings

Shows:

- Source folders.
- Auto-detected source status.
- Add watched folder.
- Remove watched folder.
- Local-only/privacy note.
- Notification toggle.
- Backfill notification behavior.

## Privacy And Safety

The app should be explicit that processing is local.

Privacy boundaries:

- No cloud sync in MVP.
- No account required.
- No conversation upload.
- No LLM analysis.
- No embeddings.
- No private API scraping.
- No Claude Desktop IndexedDB parsing in MVP.

Safety behaviors:

- Read-only access to source conversation stores.
- Never modify Claude or Codex history files.
- Gracefully skip malformed files or unsupported entries.
- Ignore encrypted Codex content.

## Error Handling

Source folders:

- Missing folder: show disconnected source status.
- Permission denied: show source needs permission.
- Folder moved: show source unavailable and allow correction.

Parsing:

- Malformed JSONL line: skip line, record source warning.
- Unsupported entry shape: skip entry.
- SQLite unavailable or locked: fall back to JSONL-only indexing.
- Encrypted content: skip content and keep metadata if available.

Achievements:

- Rule errors should disable only that rule evaluation, not the whole app.
- Unlocks should be idempotent.
- Cooldowns should prevent duplicate noisy unlocks.

## Testing Strategy

Connector tests:

- Claude JSONL parser handles string and array content.
- Codex JSONL parser handles session metadata, response items, token events, and encrypted content.
- Codex SQLite metadata reader handles missing or locked database.

Event extraction tests:

- Keyword groups produce expected events.
- Event sequences are ordered by timestamp.
- Exclusions prevent obvious false positives.

Achievement rule tests:

- Each active contract has at least one fixture.
- Cooldowns prevent duplicates.
- Historical backfill does not spam notifications.

Integration tests:

- Index sample Claude and Codex fixtures into SQLite.
- Unlock one metadata achievement.
- Unlock one keyword achievement.
- Unlock one sequence achievement.

UI tests:

- Source status appears.
- Achievement shelf renders locked and unlocked achievements.
- Notification click opens detail view.

## First Build Milestone

The first end-to-end milestone should be intentionally tiny:

1. Launch app.
2. Detect local Claude Code and Codex folders.
3. Index a small subset of real or fixture transcripts.
4. Normalize threads/messages into local SQLite.
5. Extract a few events.
6. Unlock:
   - **Achievement Unlocked: Unlocking Achievement**
   - One metadata achievement, such as **One More Prompt**
   - One keyword achievement, such as **Actually, Wait** or **Stack Trace Oracle**
7. Show a native notification.
8. Show the unlock in the achievement shelf.

## Open Decisions

- Whether first historical scan should unlock achievements silently, summarized, or normally.
- Whether normalized message text should be retained indefinitely or replaced by derived events after rules run.
- Whether to ship with all 46 active achievements visible or start with a smaller curated visible set.
- Whether to initialize this workspace as a git repository before implementation.

## References

- `docs/achievements-v1-draft.md`
- `docs/achievement-trigger-contracts-v1.jsonl`
- `docs/source-discovery-claude-codex.md`

