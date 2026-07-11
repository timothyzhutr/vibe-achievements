# Conversation Source Adapter Design

## Goal

Replace the current JSONL-path scanner with a small source-adapter boundary that
supports file, directory, and SQLite conversation stores without coupling the
achievement engine to platform-specific schemas.

## Current Problem

`SourceDiscovery` currently returns three optional folders, `AppState` computes
file fingerprints, and `Indexer` accepts only `.jsonl` URLs. `Indexer` then
guesses Claude Code versus Codex from the path or the first 512 bytes. That works
for two similar sources but cannot represent one conversation inside Cursor or
OpenCode SQLite, source-specific read consistency, or schema capability checks.

## Chosen Approach

Use one adapter per supported tool. An adapter owns:

- default and manually overridden root discovery;
- capability probing and source-specific warnings;
- enumeration of stable conversation records;
- a cheap per-record fingerprint;
- parsing one record into `ParsedTranscript`;
- strict read-only and privacy boundaries.

The shared indexer owns changed-record filtering, normalized persistence,
achievement evaluation, and global once-only unlock behavior.

Extending the existing URL list was rejected because database sessions are not
files. A universal raw-record parser was rejected because it would move schema
knowledge into the core and create unsafe access to unrelated database values.

## Core Types

```swift
public protocol ConversationSourceAdapter: Sendable {
    var sourceTool: SourceTool { get }
    var displayName: String { get }
    func discover() throws -> SourceInventory
    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript
}

public struct SourceInventory: Sendable {
    public var records: [ConversationSourceRecord]
    public var warnings: [SourceWarning]
    public var detectedRoots: [URL]
}

public struct ConversationSourceRecord: Hashable, Sendable {
    public var sourceTool: SourceTool
    public var stableID: String
    public var displayPath: String
    public var locator: SourceRecordLocator
    public var fingerprint: String
}

public enum SourceRecordLocator: Hashable, Sendable {
    case file(URL)
    case directory(root: URL, recordID: String)
    case database(database: URL, recordID: String)
}
```

`stableID` identifies one source conversation and never includes a mutable title
or timestamp. The full identity persisted by Vibe Achievements is
`<sourceTool>:<stableID>`.

## Adapter Registry And Configuration

`SourceConfiguration` gains enabled flags and optional root overrides for every
source. `ConversationSourceRegistry` creates enabled adapters from one immutable
configuration value. The app can therefore display settings without knowing
parser internals.

Manual selection always chooses a source root, never individual transcripts or
database files. Defaults remain automatic. Missing defaults are a disconnected
source, not an error.

## Fingerprints And Incremental Scans

Adapters compute fingerprints at conversation granularity:

- JSONL: detector version, file size, and modification time;
- directory-backed session: session metadata plus relevant child-file state;
- SQLite session: source schema generation, session update value, latest message
  sequence/update value, and message count.

The app persists fingerprints in:

```sql
CREATE TABLE source_records (
  source_tool TEXT NOT NULL,
  record_id TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  display_path TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  last_seen_scan_id TEXT NOT NULL,
  PRIMARY KEY (source_tool, record_id)
);
```

The existing `source_files` rows migrate by recognizing the existing Claude and
Codex path families, using the path as record ID and the already-normalized
thread ID when available. Unrecognized development rows are left behind until
the old table is retired. A detector-version prefix invalidates all relevant
fingerprints when normalized behavior changes.

## Indexing Flow

1. Build enabled adapters from source settings.
2. Discover each adapter independently; one failed source does not block others.
3. Merge inventories by `(sourceTool, stableID)` and reject duplicates within one
   adapter as warnings.
4. Compare record fingerprints with `source_records`.
5. Parse only new or changed records.
6. Upsert the normalized thread and evaluate still-locked transcript rules.
7. Record a fingerprint only after successful parsing and persistence.
8. Mark records seen in this scan and reconcile disappeared records without
   touching source data.
9. Run aggregate achievement evaluation after all changed records are stored.

Source removal deletes the app's derived thread/facts only after the same record
is absent for two complete scans. This avoids transient disappearance while a
tool rotates or replaces storage.

## Read-Only SQLite Helper

Cursor and OpenCode share `ReadOnlySQLiteSnapshot`:

- open with `SQLITE_OPEN_READONLY` and `PRAGMA query_only=ON`;
- begin a short read transaction so WAL-backed reads are consistent;
- set a short busy timeout and surface `busy` as a retryable warning;
- never use the source application's migration/database initialization code;
- never use `immutable=1` while the source may be running;
- when a stable snapshot is required, use SQLite Online Backup into an
  app-owned temporary database rather than copying only the main file.

The helper accepts explicit SQL from an adapter. It does not provide arbitrary
table enumeration to the application layer.

## Error And Status Model

Warnings have a source tool, record ID or root, stable code, and short message.
Required codes are `permissionDenied`, `sourceBusy`, `schemaUnsupported`,
`malformedRecord`, `recordChangedDuringRead`, and `duplicateRecord`.

An adapter may be:

- connected: at least one supported record found;
- empty: a valid root exists but contains no records;
- unavailable: default root missing or source disabled;
- needs attention: permission or unsupported-schema warning.

## Privacy

- Adapters use explicit path, table, column, and key allowlists.
- Credential, auth, log, cache, telemetry, checkpoint, and secret-storage data
  are never read.
- Source stores are never modified, checkpointed, migrated, or vacuumed.
- Raw source content is not logged in warnings.
- Temporary SQLite snapshots are deleted after parsing.

## Testing

- Contract tests prove stable identity, duplicate rejection, and warning
  isolation.
- Existing Claude/Codex fixtures pass unchanged through adapters.
- A failing source does not prevent another source from indexing.
- Unchanged records invoke zero parser calls.
- Failed records do not persist fingerprints.
- Two-scan removal reconciliation deletes only derived local state.
- SQLite helper tests cover WAL reads, busy errors, query-only enforcement, and
  temporary snapshot cleanup.

## Delivery Order

1. Land the adapter contract and wrap Claude Code/Codex with no behavior change.
2. Add Cursor, which is locally available for real validation.
3. Add Antigravity, gated by a current transcript fixture.
4. Add OpenCode, gated by current SQLite and legacy fixture coverage.
