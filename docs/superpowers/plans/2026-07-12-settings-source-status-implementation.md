# Settings Source Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show enabled state and latest connection state independently for every source in Settings.

**Architecture:** `AppState` publishes the statuses already returned by indexing, keyed by `SourceTool`. A pure presentation model converts enabled/status combinations into labels, symbols, details, and semantic tones; `SettingsView` only renders that model and keeps discovery inside adapters.

**Tech Stack:** Swift 6, SwiftUI, Combine, XCTest, macOS Accessibility inspection

---

### Task 1: Publish Per-Source Scan Status

**Files:**
- Modify: `Sources/vibe-achievements-app/AppState.swift`
- Test: `Tests/VibeAchievementsAppTests/AppStateTests.swift`

- [ ] **Step 1: Write a failing scan-result application test**

Add an `AppStateTests` case that applies statuses for Claude Code and Cursor and
asserts `state.sourceStatuses[.claudeCode]` and `state.sourceStatuses[.cursor]`.
Expose an internal `applySourceStatuses(_:)` helper so the test exercises the
same dictionary construction as a real scan.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AppStateTests.testPublishesLatestStatusBySourceTool`

Expected: compilation fails because `sourceStatuses` and
`applySourceStatuses(_:)` do not exist.

- [ ] **Step 3: Implement status publication**

Add:

```swift
@Published var sourceStatuses: [SourceTool: ConversationSourceStatus] = [:]

func applySourceStatuses(_ statuses: [ConversationSourceStatus]) {
    sourceStatuses = Dictionary(uniqueKeysWithValues: statuses.map { ($0.sourceTool, $0) })
}
```

Carry `[ConversationSourceStatus]` in `ScanResult`, call the helper from
`apply(_:)`, and return the complete registration-ordered status list from both
success and failure paths. Clear the dictionary before a settings-triggered
rescan so enabled sources render `Refreshing` instead of stale health.

- [ ] **Step 4: Run AppState tests and verify GREEN**

Run: `swift test --filter AppStateTests`

Expected: all `AppStateTests` pass.

- [ ] **Step 5: Commit the state change**

```bash
git add Sources/vibe-achievements-app/AppState.swift Tests/VibeAchievementsAppTests/AppStateTests.swift
git commit -m "Publish per-source connection status"
```

### Task 2: Define Connection Presentation Semantics

**Files:**
- Create: `Sources/vibe-achievements-app/SourceStatusPresentation.swift`
- Create: `Tests/VibeAchievementsAppTests/SourceStatusPresentationTests.swift`

- [ ] **Step 1: Write failing table-driven presentation tests**

Cover disabled, missing status, connected with singular/plural counts, empty,
needs-attention with warning count, and unavailable. Assert these outputs:

```swift
SourceStatusPresentation.make(isEnabled: false, status: nil).label == "Disabled"
SourceStatusPresentation.make(isEnabled: true, status: nil).label == "Refreshing"
SourceStatusPresentation.make(isEnabled: true, status: connected).detail == "7 conversations"
SourceStatusPresentation.make(isEnabled: true, status: attention).detail == "3 warnings"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter SourceStatusPresentationTests`

Expected: compilation fails because `SourceStatusPresentation` does not exist.

- [ ] **Step 3: Implement the pure presentation model**

Create a model with:

```swift
enum SourceStatusTone { case positive, caution, negative, neutral }

struct SourceStatusPresentation: Equatable {
    let label: String
    let detail: String?
    let systemImage: String
    let tone: SourceStatusTone

    static func make(
        isEnabled: Bool,
        status: ConversationSourceStatus?
    ) -> SourceStatusPresentation
}
```

Map Connected to `checkmark.circle.fill`/positive, Needs attention to
`exclamationmark.triangle.fill`/caution, Unavailable to `xmark.circle.fill`/negative,
and all other states to neutral symbols. Disabled always overrides scan status.

- [ ] **Step 4: Run presentation tests and verify GREEN**

Run: `swift test --filter SourceStatusPresentationTests`

Expected: all state mappings pass.

- [ ] **Step 5: Commit the presentation model**

```bash
git add Sources/vibe-achievements-app/SourceStatusPresentation.swift Tests/VibeAchievementsAppTests/SourceStatusPresentationTests.swift
git commit -m "Model source status presentation"
```

### Task 3: Render The Explicit Two-State Row

**Files:**
- Modify: `Sources/vibe-achievements-app/SettingsView.swift`
- Modify: `Sources/vibe-achievements-app/AppDelegate.swift`
- Test: `Tests/VibeAchievementsAppTests/SourceStatusPresentationTests.swift`

- [ ] **Step 1: Add row inputs for source identity and status**

Pass `sourceTool` and `status: state.sourceStatuses[sourceTool]` into each
`SourceDirectoryRow`. Inside the row, derive:

```swift
let presentation = SourceStatusPresentation.make(
    isEnabled: isEnabled,
    status: status
)
```

- [ ] **Step 2: Render two labeled fields**

Place an unframed two-column `HStack` beneath the source title:

```swift
HStack(spacing: 28) {
    LabeledContent("Enabled") {
        Toggle(isOn: $isEnabled) { Text(isEnabled ? "On" : "Off") }
            .toggleStyle(.switch)
    }
    LabeledContent("Connection") {
        Label(presentation.displayText, systemImage: presentation.systemImage)
            .foregroundStyle(presentation.color)
    }
}
```

Keep the path and Choose/Reset controls beneath it. Use semantic color mapping
in a private SwiftUI extension and provide a combined accessibility label such
as `Claude Code connection, Connected, 7 conversations`.

Wrap the source list in a `ScrollView`, retain a constrained content width, and
increase the reusable Settings window content size to `620x640` so all five
expanded rows remain comfortable without clipping on the initial viewport.

- [ ] **Step 3: Build and run all tests**

Run: `swift test && swift build && git diff --check`

Expected: all tests pass, both targets build, and the diff has no whitespace errors.

- [ ] **Step 4: Rebuild and inspect the macOS app**

Run:

```bash
Scripts/make-dmg.sh
open dist/VibeAchievements.app
```

Open Settings and verify all five rows at `620x640`: no overlap, long paths
truncate in the middle, disabled overrides connection, and live source states
match the achievement window summary.

- [ ] **Step 5: Commit the UI and refreshed documentation**

```bash
git add Sources/vibe-achievements-app/SettingsView.swift Sources/vibe-achievements-app/AppDelegate.swift docs/superpowers
git commit -m "Show source connection status in settings"
```
