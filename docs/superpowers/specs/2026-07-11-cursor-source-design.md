# Cursor Conversation Source Design

## Goal

Index regular local Cursor chat history on macOS without reading credentials,
modifying Cursor state, or depending on one undocumented storage generation.

## Scope

Included:

- regular local agent/composer chats;
- current global SQLite/KV storage;
- newer agent transcript JSONL;
- legacy per-workspace composer storage;
- project identity, message roles/text/order, and available timestamps.

Excluded:

- remote Background Agent chats;
- restoring or editing Cursor history;
- checkpoints, diffs, attached files, secret storage, telemetry, and AI tracking;
- inferred token counts beyond the shared text estimate when raw usage is absent.

## Default Storage

```text
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
~/Library/Application Support/Cursor/User/workspaceStorage/<workspace-id>/state.vscdb
~/Library/Application Support/Cursor/User/workspaceStorage/<workspace-id>/workspace.json
~/.cursor/projects/<project-slug>/agent-transcripts/**/<conversation-id>.jsonl
```

`~/.cursor/ai-tracking/ai-code-tracking.db` is derived analytics and is not a
conversation source.

## Capability Generations

The adapter probes these generations independently:

1. Global `cursorDiskKV` records: `composerData:<id>`,
   `bubbleId:<composer>:<bubble>`, and required `agentKv:blob:<hash>` text blobs.
2. Agent transcript JSONL under `~/.cursor/projects`.
3. Legacy workspace `ItemTable['composer.composerData']` plus workspace KV rows.

Table existence is not enough. A generation is usable only when its required
keys contain parseable conversation records. For one conversation, the adapter
selects the highest generation with complete ordered text and does not concatenate
multiple representations.

## SQLite Access

Both global and workspace databases are WAL-mode SQLite. The adapter uses the
shared read-only helper and allowlists only:

```text
ItemTable: composer.composerHeaders, composer.composerData
cursorDiskKV: composerData:*, bubbleId:*, agentKv:blob:*
composerHeaders: metadata columns and value
```

`checkpointId:*`, `messageRequestContext:*`, secret storage, and every unrelated
row are ignored.

## Conversation And Project Identity

- Stable conversation ID: `cursor:<workspaceIdentity>:<composerId>`.
- Message ID: source `bubbleId` or agent-record ID; transcript fallback uses
  `<conversationId>:<lineOrdinal>`.
- Project path priority: `workspaceIdentifier.uri`, matching `workspace.json`
  `folder`, then `workspace.json` workspace file.
- Path-derived `~/.cursor/projects` slugs are not reversed into paths. They are
  matched through SQLite/workspace metadata when possible.
- Unknown project identity remains `unknown-project` and is excluded from
  cross-project achievements.

## Message Normalization

Global/legacy composers use `fullConversationHeadersOnly` for ordering. Each
bubble is loaded by exact `bubbleId` key. Text priority is `text`, `rawText`, then
plain text extracted from supported `richText`. Human bubbles map to `.user`;
assistant/model bubbles map to `.assistant`; tool/system records are ignored
unless they contain explicit conversational text.

Agent transcript JSONL uses line order. Records with `role` values map directly;
text comes from supported `message.content` text items. `turn_ended` records
close turns but do not become messages.

Composer `createdAt`/`lastUpdatedAt` are Unix milliseconds. Bubble timestamps may
be ISO-8601. Missing transcript timestamps remain nil; file mtime may set thread
`updatedAt` but never message time.

## Incremental Fingerprint

- SQLite composer: schema generation, composer `lastUpdatedAt`, and ordered
  bubble-ID digest. KV-only legacy stores additionally hash composer payloads.
- JSONL transcript: detector version, size, and mtime.
- Legacy composer: workspace ID, composer ID, update value, and ordered bubble-ID
  digest.

The adapter reads only composers whose cheap metadata fingerprint changed.
The installed Cursor schema contains unlinked `agentKv:blob` rows; those are not
guessed into conversations until a persisted composer/bubble reference is
observed and can be fixture-tested without scanning unrelated blob content.

## Duplicate Handling

Deduplicate first by composer/conversation ID. Cross-generation records with
different IDs remain distinct in V1; incremental normalized-content ownership is
deferred so periodic discovery never rereads all conversation text.

## Local Validation Gate

Cursor 3.9.16 and substantial local storage are available on this Mac. Before
shipping, validate read-only enumeration counts, synthetic fixture parsing, one
real conversation's roles/order/project association, live-WAL reading, and an
unchanged rescan. Never capture real text in fixtures or logs.

## Failure Behavior

- Busy database: retry on the next scan and preserve prior derived data.
- Unknown schema: report `schemaUnsupported`; do not fall through to another
  platform parser.
- Missing bubble: preserve other messages; if no usable messages remain, retry
  the record on the next scan without replacing prior derived state.
- Database changes during enumeration: each database is read inside one direct,
  consistent SQLite transaction.
- Missing workspace metadata: index global counts with unknown project identity.

## Acceptance Criteria

- Current, transcript, and legacy fixtures normalize to equivalent threads.
- One stored conversation is emitted once even when two generations coexist.
- Cursor running during a scan is not blocked or modified.
- Background Agent remote history is never represented as locally complete.
- No query touches non-allowlisted KV keys.
- A second unchanged scan parses zero Cursor conversations.
