# OpenCode Conversation Source Design

## Goal

Index current and legacy OpenCode local sessions through explicit read-only
schema readers without touching auth, logs, migrations, or source state.

## Default Storage And Overrides

The data root is `${XDG_DATA_HOME:-~/.local/share}/opencode`.

Discovery order:

1. `OPENCODE_DB` when supplied to the Vibe Achievements process;
2. `<data-root>/opencode.db`;
3. `<data-root>/opencode-*.db` for channel builds;
4. legacy `<data-root>/storage`.

`OPENCODE_DB` may be absolute or relative to the data root. Manual settings choose
the OpenCode data root. `auth.json`, logs, configuration, caches, and desktop UI
state are excluded.

## Supported Generations

### Current Ordered SQLite

Use `session`, `project`, `project_directory`, and `session_message` when
`session_message` exists and contains rows for the session. Messages are ordered
by monotonic `seq`. Reconstruct fields promoted to columns (`id`, `type`,
timestamps) before decoding `data` JSON.

User messages read `text`. Assistant messages concatenate ordered `content`
items of type `text`. System/synthetic/shell/compaction/switch records are not
conversation turns unless they contain explicitly supported visible text.

### Compatibility SQLite

When a session has no `session_message` rows, read `message` ordered by
`time_created,id` and join `part` ordered by `time_created,id`. Reconstruct IDs
and foreign keys omitted from `data`. Concatenate text parts only.

### Legacy JSON

```text
storage/project/<project-id>.json
storage/session/<project-id>/<session-id>.json
storage/message/<session-id>/<message-id>.json
storage/part/<message-id>/<part-id>.json
```

Use legacy JSON only for session IDs absent from supported SQLite databases.
Parse retries when child-file size/mtime changes during the read.

## Identity And Normalization

- Stable record ID: opaque OpenCode session ID.
- Normalized thread ID: `opencode:<session-id>`.
- Message ID: source message ID.
- Project identity priority: joined project directory/worktree mapping, session
  directory, then unknown.
- OpenCode project IDs remain opaque and are not used as cross-tool project keys.
- Timestamps are epoch milliseconds when present.
- Raw tokens come from session aggregates or assistant token structures. Use one
  source of truth and never sum cumulative session totals with message totals.

## Generation Selection And Deduplication

For each session ID, select exactly one generation:

1. current `session_message` rows;
2. compatibility `message` + `part` rows;
3. legacy JSON.

Do not concatenate compatibility and current tables. Channel databases are
independent stores; exact normalized role/text duplicates are collapsed by local
digest, while distinct session IDs remain distinct.

## Incremental Fingerprints

- Current SQLite: schema generation, session update time, maximum `seq`, and
  `session_message` count.
- Compatibility SQLite: session update time, maximum message update time/ID, and
  message/part counts.
- Legacy JSON: session metadata plus sorted relevant message/part size and mtime
  tuples.

Schema capability is checked from tables and columns rather than OpenCode version
strings.

## SQLite Safety

Use `ReadOnlySQLiteSnapshot`, never OpenCode's runtime database initializer. The
source uses WAL, so reading/copying only the main database is invalid. A busy
database produces a retryable warning and preserves previous derived data.

Queries explicitly name required tables/columns. Unknown schema variants are
reported as unsupported rather than guessed.

## Local Validation Gate

OpenCode is not installed on this Mac. Implementation uses synthetic fixtures
based on pinned upstream schemas for current SQLite, compatibility SQLite, and
legacy JSON. The source remains experimental until a local installation creates
sessions in each available current representation and an unchanged rescan is
validated.

## Failure Behavior

- Multiple channel databases: enumerate each with database-qualified record IDs
  and collapse exact content duplicates.
- Missing text part/blob: skip the item and warn once per session.
- Migrated timestamp with uncertain provenance: preserve it as source time; do
  not claim exact original message time in UI.
- Unknown project mapping: retain global history with unknown project identity.
- Unsupported tables/columns: needs-attention source state.

## Acceptance Criteria

- Current, compatibility, and legacy fixtures normalize to equivalent threads.
- A session represented in multiple generations emits once using priority order.
- `session_message.seq` controls current message order.
- Tokens are not double-counted.
- WAL-backed databases are read consistently without source writes.
- Auth and log files are never enumerated or opened.
- A second unchanged scan parses zero OpenCode sessions.

