# Source Discovery: Claude + Codex Conversation History

Date: 2026-07-04

This note captures what we can read locally for the first version of the achievement app. The goal is a lightweight watcher/indexer, so stable plaintext JSONL sources are preferred. Browser/Electron caches, private APIs, and fragile reverse-engineered stores should be avoided for MVP.

## Summary

Claude Code and Codex both expose useful local transcript data.

- **Claude Code:** viable MVP source. Transcripts are JSONL under `~/.claude/projects/<project>/<session-id>.jsonl`.
- **Codex:** viable MVP source. Transcripts are JSONL under `$CODEX_HOME/sessions` and `$CODEX_HOME/archived_sessions`, defaulting to `~/.codex/...`.
- **Claude Desktop / claude.ai app:** not recommended for MVP. Local app storage exists under `~/Library/Application Support/Claude`, but it appears to use browser-style IndexedDB/LevelDB storage. That is more brittle and less aligned with a lightweight app.

## Local Validation On This Laptop

Validated on `/Users/Timothy` on 2026-07-04:

```text
Claude Code transcript files found: 4
Codex transcript files found: 17
Codex SQLite thread records found: 8
```

Validated Claude Code fields from local JSONL:

```text
type
timestamp
sessionId
cwd
gitBranch
message.role
message.content
message.usage
```

Validated Codex fields from local JSONL:

```text
session_meta.payload.id
session_meta.payload.cwd
session_meta.payload.source
session_meta.payload.model_provider
response_item.payload.role
response_item.payload.content
event_msg.payload.type
event_msg.payload.info.model_context_window
event_msg.payload.info.total_token_usage
```

Validated Codex fields from local SQLite:

```text
threads.id
threads.rollout_path
threads.created_at
threads.updated_at
threads.cwd
threads.title
threads.tokens_used
threads.model
threads.preview
```

## Claude Code

### Documented Location

Anthropic documents Claude Code transcript storage here:

- `~/.claude/projects/<project>/<session-id>.jsonl`
- `<project>` is the working directory path with non-alphanumeric characters replaced by `-`.
- Each line is a JSON object for a message, tool use, or metadata entry.
- Anthropic warns that the direct file entry format is internal and can change between versions.

Sources:

- https://code.claude.com/docs/en/sessions
- https://code.claude.com/docs/en/agent-sdk/session-storage
- https://code.claude.com/docs/en/claude-directory

### Local Findings

Found local Claude Code transcript files under:

```text
/Users/Timothy/.claude/projects/<project-slug>/<session-id>.jsonl
```

Example observed project path:

```text
/Users/Timothy/.claude/projects/-Users-Timothy-Documents-Cross-Platform-LLM-App/ecd53d52-46eb-47f2-9512-e92698c8e2a7.jsonl
```

Observed top-level entry types:

```text
user
assistant
attachment
queue-operation
custom-title
ai-title
last-prompt
mode
```

Observed useful top-level fields on `user` / `assistant` entries:

```text
type
timestamp
sessionId
uuid
parentUuid
cwd
gitBranch
message
version
userType
```

Observed useful `message` fields:

```text
role
content
model
usage
diagnostics
stop_reason
```

Notes:

- User message content may be a string or an array.
- Assistant message content is often an array.
- Assistant usage includes token-ish fields such as `input_tokens`, `output_tokens`, `cache_read_input_tokens`, and `cache_creation_input_tokens`.
- `cwd` is available and should be our main project identity signal.
- `gitBranch` is available and may help with project context, but should not be required.

### Claude MVP Connector Shape

Watch:

```text
~/.claude/projects/**/*.jsonl
```

Parse:

- One JSON object per line.
- Keep `type` in `user`, `assistant`, and optionally `attachment`.
- Extract timestamp, session id, cwd, git branch, role, text content, rough character count, and token usage when present.

Avoid for MVP:

- Depending on exact internal entry shapes beyond conservative field checks.
- Parsing Claude Desktop / claude.ai IndexedDB.
- Using private APIs.

## Codex

### Documented Location

OpenAI documents Codex transcript and archive locations:

- Session transcripts: `$CODEX_HOME/sessions`, default `~/.codex/sessions`
- Archived sessions: `$CODEX_HOME/archived_sessions`, default `~/.codex/archived_sessions`

OpenAI docs also mention that session IDs can be found in files under `~/.codex/sessions`, and that local history persistence is configurable under `CODEX_HOME`.

Sources:

- https://developers.openai.com/codex/app/troubleshooting
- https://developers.openai.com/codex/cli/features
- https://developers.openai.com/codex/config-advanced
- https://developers.openai.com/codex/config-reference

### Local Findings

Found local Codex session files under:

```text
/Users/Timothy/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
/Users/Timothy/.codex/archived_sessions/rollout-*.jsonl
/Users/Timothy/.codex/session_index.jsonl
```

Found local Codex SQLite state under:

```text
/Users/Timothy/.codex/sqlite/state_5.sqlite
/Users/Timothy/.codex/sqlite/codex-dev.db
/Users/Timothy/.codex/logs_2.sqlite
```

Observed `session_index.jsonl` fields:

```text
id
thread_name
updated_at
```

Observed transcript entry types in `rollout-*.jsonl`:

```text
session_meta
event_msg
response_item
turn_context
```

Observed useful `session_meta.payload` fields:

```text
id
cwd
source
model_provider
originator
git
timestamp
cli_version
```

Observed useful `response_item.payload` fields:

```text
type
role
content
summary
encrypted_content
```

Observed useful `event_msg.payload` types:

```text
task_started
user_message
agent_message
token_count
task_complete
```

Observed `token_count` info fields:

```text
last_token_usage
total_token_usage
model_context_window
```

Observed `state_5.sqlite` `threads` columns:

```text
id
rollout_path
created_at
updated_at
source
model_provider
cwd
title
tokens_used
has_user_event
archived
git_sha
git_branch
git_origin_url
cli_version
first_user_message
model
reasoning_effort
thread_source
preview
```

Notes:

- `state_5.sqlite.threads` is a strong lightweight index for thread metadata.
- `rollout_path` links thread metadata to transcript JSONL.
- `tokens_used` is available at thread level, which helps achievements like **The First Big Door**.
- `cwd` is available and should be our main project identity signal.
- Some response items can include `encrypted_content`; MVP should only process plaintext content/events that are present.

### Codex MVP Connector Shape

Watch:

```text
$CODEX_HOME/sessions/**/*.jsonl
$CODEX_HOME/archived_sessions/*.jsonl
```

Optionally read:

```text
$CODEX_HOME/sqlite/state_5.sqlite
$CODEX_HOME/session_index.jsonl
```

Parse:

- Prefer SQLite `threads` for project/thread metadata if available.
- Parse transcript JSONL for user/assistant text, token events, and tool/event indicators.
- Ignore encrypted content and process only plaintext fields.

Avoid for MVP:

- Depending on Codex Electron/browser cache files under `~/Library/Application Support/Codex`.
- Depending on logs as a primary conversation source.
- Treating private app databases as stable API unless we only use them opportunistically.

## Data Fields We Can Likely Normalize

A shared normalized thread/message shape should be feasible:

```text
source_tool: claude_code | codex
thread_id
project_path
project_key
title
created_at
updated_at
message_count
user_turn_count
assistant_turn_count
estimated_tokens
messages[]
```

Per message:

```text
message_id
thread_id
source_tool
role
timestamp
text
char_count
token_count_input
token_count_output
raw_type
```

Project identity:

1. Prefer explicit `cwd`.
2. Fall back to path-derived project slug for Claude.
3. Fall back to transcript parent folder or thread metadata if `cwd` is missing.

## Achievement Detection Implications

Very viable from metadata:

- **One More Prompt**
- **The Message Had Mass**
- **The First Big Door**
- **Multiclassing**
- **Changed Lanes**
- **Co-op Campaign**
- **Found Your Way Back**
- **Keeper of Small Fires**

Viable from lightweight text patterns:

- **Actually, Wait**
- **Stack Trace Oracle**
- **Context Window Sunset**
- **Token Budget Lifestyle**
- **It Works, Therefore It Is**
- **Cache Clearing Ritual**
- **rm -rf**
- **Shipwright**
- **CSS Negotiations**

Needs conservative handling:

- **Rubber Duck With A GPU**
- **Two Opinions Enter**
- **The App Has Opinions**

## Open Questions

- Does Codex `CODEX_HOME` always default to `~/.codex` in the desktop app, or can the app expose a different active home? We can detect via environment/config and fall back to `~/.codex`.
- How often do Claude Code internal JSONL shapes change in practice? We should parse defensively and store only normalized fields.
- Should archived sessions count immediately on first scan, or should the app avoid flooding achievements from historical data? This matters for pacing.

## Recommendation

Build MVP connectors for **Claude Code** and **Codex local transcripts**, not Claude Desktop IndexedDB.

The first technical milestone should be:

1. Discover default source folders.
2. Let the user add/correct watched folders.
3. Index normalized thread/message metadata locally.
4. Unlock one metadata achievement and one keyword achievement from real local transcripts.
