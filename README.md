# Vibe Achievements

A lightweight, **local-only macOS menu bar app** that turns your AI-assisted
coding history into Steam-style achievements. It quietly watches the transcripts
that tools like **Claude Code** and **Codex** already write to disk, extracts
cheap keyword/metadata signals, and unlocks playful achievements — *"Actually,
Wait"*, *"rm -rf"*, *"Stack Trace Oracle"* — as your vibe-coding patterns emerge.

No cloud, no account, no conversation upload, no LLM analysis. Everything stays
on your machine.

> Status: early MVP. The full local pipeline works end to end (discover → parse
> → store → extract → unlock → notify), with a small starter set of achievements
> wired up. See [Roadmap](#roadmap).

## What it does

- Auto-detects local Claude Code and Codex transcript folders.
- Parses transcripts defensively (malformed lines/files are skipped, never fatal).
- Normalizes everything into a small local SQLite database.
- Extracts lightweight events (corrections, stack traces, destructive cleanup,
  recovery, success, long threads…).
- Evaluates achievement rules and unlocks them, scoped by each achievement's
  cooldown (per-thread, per-project, or global).
- Fires native macOS notifications for new unlocks; the first historical
  backfill is collapsed into a single summary instead of a burst.
- Shows an achievement shelf and a source/status window from the menu bar.

## How it works

```
 ~/.claude/projects/**/*.jsonl        SourceDiscovery
 ~/.codex/sessions/**/*.jsonl   ─────►  (find transcript files)
                                            │
                                            ▼
                              ClaudeCodeParser / CodexParser
                                   (normalize threads+messages)
                                            │
                                            ▼
                                    SQLiteStore (upsert)
                                            │
                                            ▼
                                     EventExtractor
                               (keyword / metadata signals)
                                            │
                                            ▼
                                   AchievementEngine
                          (rules + cooldown-scoped unlock keys)
                                            │
                                            ▼
                          SQLite unlocks ──► notifications + shelf
```

Change detection is persisted (a file fingerprint of mtime+size), so only new or
changed transcripts are re-parsed across launches. Indexing runs off the main
thread; the UI never blocks on a scan.

### Validated local sources

- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex sessions: `$CODEX_HOME/sessions/**/*.jsonl` (default `~/.codex/sessions`)
- Codex archived sessions: `$CODEX_HOME/archived_sessions/*.jsonl`

Source stores are read **read-only**; the app never modifies your history.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16 / recent Swift toolchain)

## Build & test

```bash
swift build          # build everything
swift test           # run the test suite (31 tests)
```

## Running

### Menu bar app

```bash
swift run vibe-achievements-app
```

Runs as a menu-bar **accessory** app (no Dock icon). Use the **Vibe** menu bar
item to open the achievement shelf, trigger a manual **Scan Now**, open Settings,
or quit.

> Note: notifications require a real app bundle identifier. When launched via
> `swift run`, the menu bar UI and indexing work, but notification delivery is
> unreliable until the executable is wrapped in a proper `.app` bundle (see
> [Roadmap](#roadmap)).

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

## Project layout

```
Package.swift
Sources/
  VibeAchievementsCore/         # testable core (no UI)
    Models.swift                # normalized thread/message model
    SourceDiscovery.swift       # find transcript folders + files
    ClaudeCodeParser.swift      # Claude Code JSONL parser
    CodexParser.swift           # Codex JSONL parser
    TextContent.swift           # shared content extraction
    AchievementContract.swift   # contract loader (+ bundled V1)
    EventExtractor.swift        # keyword/metadata event signals
    AchievementEngine.swift     # rules + cooldown-scoped unlocks
    SQLiteStore.swift           # local SQLite persistence
    Indexer.swift               # orchestrates a scan
    Resources/
      achievement-trigger-contracts-v1.jsonl   # bundled contracts
  vibe-achievements-cli/        # headless indexer
  vibe-achievements-app/        # SwiftUI + AppKit menu bar app
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

- Wire the remaining achievements (currently ~5 of 46 rules are implemented:
  the first-unlock meta achievement plus `actually_wait`, `one_more_prompt`,
  `rm_rf`, and `it_works_therefore_it_is`).
- Enforce time-windowed cooldowns (e.g. `once_per_project_per_7_days` is
  currently treated as once-per-project).
- Package a signed/notarized `.app` bundle and a `.dmg` for distribution.
- Cross-tool achievements (same project across Claude + Codex).

## Design docs

- [Design spec](docs/superpowers/specs/2026-07-04-vibe-coding-achievements-design.md)
- [MVP implementation plan](docs/superpowers/plans/2026-07-04-vibe-achievements-mvp.md)
- [Achievement list (v1 draft)](docs/achievements-v1-draft.md)
- [Source discovery notes](docs/source-discovery-claude-codex.md)

## License

Not yet licensed. All rights reserved by the author until a license is chosen.
