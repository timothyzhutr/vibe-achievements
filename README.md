# Vibe Achievements

A lightweight, **local-only macOS menu bar app** that turns your AI-assisted
coding history into Steam-style achievements. It quietly watches the transcripts
that tools like **Claude Code** and **Codex** already write to disk, extracts
cheap keyword/metadata signals, and unlocks playful achievements — *"Actually,
Wait"*, *"rm -rf"*, *"Stack Trace Oracle"* — as your vibe-coding patterns emerge.

No cloud, no account, no conversation upload, no LLM analysis. Everything stays
on your machine.

> Status: MVP. The full local pipeline works end to end (discover → parse →
> store → extract → unlock → notify), with all single-transcript achievements
> wired up (27 of 46). The remaining 19 need cross-transcript aggregation. See
> [Roadmap](#roadmap).

## What it does

- Auto-detects local Claude Code and Codex transcript folders, with Settings
  controls for correcting or disabling each source.
- Parses transcripts defensively (malformed lines/files are skipped, never fatal).
- Normalizes everything into a small local SQLite database.
- Extracts lightweight events (corrections, stack traces, destructive cleanup,
  recovery, success, long threads, context/budget talk, UI work, shipping…).
- Evaluates achievement rules and unlocks each one **once per user, ever**
  (global identity — the project/thread where it first fired is kept for display
  only).
- Fires one native macOS notification per newly unlocked achievement, exactly
  once, tracked in the database so it never re-notifies across scans or restarts.
- Shows an achievement shelf and a source/status window from the menu bar.

## How it works

```
 Source settings ──► ConversationSourceRegistry
                              │
                              ▼
                 ClaudeCode / Codex adapters
                  (discover + fingerprint records)
                              │
                              ▼
                     Incremental Indexer
                (parse changed records + persist)
                              │
                              ▼
             EventExtractor ──► AchievementEngine
                              │
                              ▼
                 SQLite unlocks ──► notifications + shelf
```

Change detection is persisted by typed source identity in `source_records`, so
only new or changed conversations are re-parsed across launches. Failed records
are retried, one unavailable source does not block another, and derived local
threads are removed only after two complete scans where the source record is
absent. Indexing runs off the main thread; the UI never blocks on a scan.

### Validated local sources

- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex sessions: `$CODEX_HOME/sessions/**/*.jsonl` (default `~/.codex/sessions`)
- Codex archived sessions: `$CODEX_HOME/archived_sessions/*.jsonl`

Source stores are read **read-only**; the app never modifies your history.

### Source settings

Open **Settings** from the menu bar item to control watched sources:

- Toggle `Claude Code` or `Codex` scanning on or off.
- Use **Choose...** to point Claude Code at a projects folder, such as
  `~/.claude/projects`.
- Use **Choose...** to point Codex at its home folder, such as `~/.codex`; the
  app derives `sessions` and `archived_sessions` below that folder.
- Use **Reset** to return a source to auto-detection.

Settings are stored locally in `UserDefaults` and trigger a quiet rescan after
changes.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16 / recent Swift toolchain)

## Build & test

```bash
swift build          # build everything
swift test           # run the test suite
```

## Running

### Menu bar app

```bash
swift run vibe-achievements-app
```

Runs as a menu-bar **accessory** app (no Dock icon). Use the **Vibe** menu bar
item to open the achievement shelf, open Settings, or quit. Scans run
automatically on launch, when a window opens, and on a periodic timer. Settings
lets you enable/disable Claude Code and Codex sources, choose manual source
folders, and reset back to auto-detection.

> Note: notifications require a real app bundle identifier, so they are
> disabled when launched via `swift run` (the menu bar UI and indexing still
> work). Use the packaged app for the full experience — see
> [Packaging](#packaging-app--dmg).

### CLI (headless indexer)

Useful for development and for verifying the pipeline against fixtures:

```bash
swift run vibe-achievements-cli <contracts.jsonl> <store.sqlite> [transcript.jsonl ...]

# Example against the bundled fixtures:
swift run vibe-achievements-cli \
  docs/achievement-trigger-contracts-v1.jsonl \
  /tmp/vibe.sqlite \
  Tests/VibeAchievementsCoreTests/Fixtures/claude-sample.jsonl \
  Tests/VibeAchievementsCoreTests/Fixtures/codex-sample.jsonl
```

Unlocks are printed to stdout; skipped/unreadable files are reported to stderr.

## Packaging (.app / .dmg)

```bash
Scripts/make-app.sh   # release build → dist/VibeAchievements.app (ad-hoc signed)
Scripts/make-dmg.sh   # the above + dist/VibeAchievements-<version>.dmg
```

The `.app` bundle is what gives the app a real bundle identifier, which is
required for native notifications. The `.dmg` is the standard drag-to-install
disk image for handing the app to another Mac.

The build is **ad-hoc signed** — fine for your own machine. On another Mac,
right-click the app and choose *Open* to get past Gatekeeper. Public
distribution without warnings would additionally need an Apple Developer ID
signature and notarization ($99/yr Apple Developer Program).

## Project layout

```
Package.swift
Sources/
  VibeAchievementsCore/         # testable core (no UI)
    Models.swift                # normalized thread/message model
    ConversationSourceAdapter.swift  # shared source/record contract
    ConversationSourceRegistry.swift # build enabled adapters from settings
    SourceDiscovery.swift       # resolve default and overridden roots
    ClaudeCodeSourceAdapter.swift
    CodexSourceAdapter.swift
    ReadOnlySQLiteSnapshot.swift # safe helper for future DB-backed adapters
    ClaudeCodeParser.swift      # Claude Code JSONL parser
    CodexParser.swift           # Codex JSONL parser
    TextContent.swift           # shared content extraction
    AchievementContract.swift   # contract loader (+ bundled V1)
    EventExtractor.swift        # keyword/metadata event signals
    EventSummary.swift          # per-thread event facts (presence/count/sequence)
    AchievementEngine.swift     # rule table + global once-per-user unlocks
    SQLiteStore.swift           # local SQLite persistence
    Indexer.swift               # orchestrates a scan
    Resources/
      achievement-trigger-contracts-v1.jsonl   # bundled contracts
  vibe-achievements-cli/        # headless indexer
  vibe-achievements-app/        # SwiftUI + AppKit menu bar app
    AppSourceSettings.swift     # persisted Claude/Codex source settings
Tests/VibeAchievementsCoreTests/
docs/                           # design spec, plan, achievement list
```

### Achievement contracts

The 50 achievement definitions live in
[`docs/achievement-trigger-contracts-v1.jsonl`](docs/achievement-trigger-contracts-v1.jsonl)
(46 active, 3 dropped-but-kept-for-history, 1 reserved for a future third tool).
A byte-for-byte copy is bundled into `Sources/VibeAchievementsCore/Resources/`
so the app can load it without a docs dependency; a test
(`ContractsCanonicalTests`) fails if the two copies ever drift.

## Privacy

- Local-only processing. No cloud sync, no account, no telemetry.
- No conversation upload, no LLM analysis, no embeddings.
- Read-only access to source transcripts; history files are never modified.
- Encrypted Codex content is ignored; only plaintext fields are read.

## Roadmap

- Wire the remaining 19 achievements. These need a cross-transcript evaluation
  stage — counts, time windows, and multi-tool/multi-model spans over the stored
  `threads` table (e.g. *"Party Finder"*, *"Model Diplomat"*, *"Platinum
  Memory"*) — which the current single-transcript engine deliberately doesn't do.
- Developer ID signing + notarization for public distribution (local `.app`/
  `.dmg` packaging already works — see [Packaging](#packaging-app--dmg)).

## Design docs

- [Design spec](docs/superpowers/specs/2026-07-04-vibe-coding-achievements-design.md)
- [MVP implementation plan](docs/superpowers/plans/2026-07-04-vibe-achievements-mvp.md)
- [Achievement list (v1 draft)](docs/achievements-v1-draft.md)
- [Source discovery notes](docs/source-discovery-claude-codex.md)

## License

Not yet licensed. All rights reserved by the author until a license is chosen.
