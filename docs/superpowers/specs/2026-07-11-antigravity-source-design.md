# Antigravity Conversation Source Design

## Goal

Index documented Antigravity IDE and CLI trajectory transcripts as local
conversations while tolerating undocumented step variants and partial writes.

## Default Storage

```text
~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl
~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl
```

Only `transcript.jsonl` is scanned. `transcript_full.jsonl`, artifacts, scratch
files, Application Support databases, LevelDB, logs, caches, and auth state are
excluded.

## Source Identity

- Stable ID: `antigravity:<ide|cli>:<conversation-directory-uuid>`.
- Message ID: source step ID when present, otherwise conversation ID plus line
  ordinal.
- Project path: first explicit workspace path for IDE; exact CLI current/project
  directory for CLI.
- CLI subdirectory identity is preserved rather than collapsed to the Git root,
  matching Antigravity's directory-scoped history behavior.

## Tolerant Trajectory Parser

The JSONL schema is treated as a discriminated step union, not an OpenAI-style
chat format. The parser decodes each line to a bounded `JSONValue`, then recognizes
field shapes for:

- user input or `userMessage` -> `.user`;
- planner/model response text -> `.assistant`;
- ephemeral/system text -> `.system` only when it is visible conversation text;
- tool calls/results and artifacts -> ignored for normalized messages.

Unknown valid step variants are skipped and counted in one thread warning. They
do not fail the transcript. Empty/tool-only trajectories do not emit threads.

Line order is authoritative. Source timestamps are used only when a known field
parses as ISO-8601 or epoch milliseconds. Missing message timestamps remain nil.
File mtime may populate thread `updatedAt`. Token usage is populated only when a
recognized persisted counter exists; otherwise the shared text estimate applies.

## Safe Reads

- Read only newline-terminated records; ignore a partial final line.
- Stat size/mtime before and after reading.
- Retry once when the file changes during parsing.
- Never lock, truncate, rewrite, or repair a transcript.
- Continue periodic scans even if FSEvents is later added as a hint.

## Forks And Imports

Fork and IDE/CLI import can clone history under a new conversation UUID. Exact
normalized duplicates are collapsed by a local role/text digest, preferring IDE
over imported CLI when both are otherwise equal. Prefix-related forks remain
separate conversations in V1 of this adapter; the known consequence is that a
shared prefix may contribute twice to cumulative counts. Prefix-aware lineage is
deferred because it requires message-level aggregate deduplication across every
source, not an Antigravity-only heuristic.

## Local Validation Gate

Antigravity is installed but its documented `brain` directory is currently
empty. The adapter ships as experimental until a current Antigravity 2.0 IDE or
CLI conversation is generated and sanitized into fixtures. Application Support
state from older Antigravity versions is not accepted as a substitute.

## Failure Behavior

- Missing brain root: source unavailable, no warning.
- Existing empty brain root: connected but empty.
- Partial final JSONL record: ignore and retry on the next scan.
- Malformed complete line: skip and report one record warning.
- Recognized transcript with no user/assistant text: skip as unsupported content.
- Permission denied: needs-attention source state.

## Acceptance Criteria

- IDE and CLI roots are discovered independently.
- `transcript_full.jsonl` is never enumerated.
- User and planner-response fixture steps normalize in line order.
- Unknown and tool-only variants do not become user turns.
- A partial final line does not fail earlier valid history.
- Exact imported duplicates emit one normalized thread.
- A second unchanged scan parses zero Antigravity transcripts.

