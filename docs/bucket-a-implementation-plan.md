# Bucket A Implementation Plan

Wiring the 22 **single-transcript** achievements that can be detected from one
`.jsonl` file alone (keyword presence, occurrence counts, ordered sequences, and
per-message/thread metadata). The 19 Bucket B achievements are deferred — they
need cross-transcript, time-window, or tool-usage aggregation over the `threads`
table and don't belong here.

Branch: `Claude`. Local achievement history already cleared, so a fresh index
will re-notify everything once these land.

---

## 0. What's already there

- **Engine** (`AchievementEngine.evaluate`) currently hardcodes 5 `unlock(...)`
  calls + the "first achievement" meta rule. Detection primitives that exist:
  `contains` (presence) and `hasSequence` (ordered subsequence, stable-sorted by
  `(timestamp, offset)`).
- **Extractor** (`EventExtractor.extract`) is an if-chain emitting these
  `EventType`s today:
  `correctionLanguageSeen`, `implementationOrFixSeen`, `stackTraceSeen`,
  `destructiveCleanupSeen`, `recoverySeen`, `successSeen`, `oneMorePromptSeen`,
  `longMessageSeen`.
- Two of the 22 are **almost free** because the event already exists:
  - `#19 stack_trace_oracle` → `stackTraceSeen` (expand keywords)
  - `#13 the_message_had_mass` → `longMessageSeen` (already emitted at ≥2000 chars)

---

## 1. Prep

- **Bump `detectorFingerprintVersion` → `"detectors-v3"`**
  (`Sources/vibe-achievements-app/AppState.swift`). File fingerprints embed this
  string, so bumping it forces every transcript to be re-indexed against the new
  detectors. Without it, unchanged files keep their old fingerprints and the new
  achievements never fire on existing installs.
- `AppStateTests.testFingerprintIncludesDetectorVersion` already asserts the
  prefix, so it keeps passing after the bump.

---

## 2. Enabling architecture (do once — unblocks all 22)

Adding 22 more hardcoded `unlock(...)` blocks + 20 more `if` branches would bloat
both files. Three small, self-contained refactors keep it clean and testable.

### (a) `EventSummary` — precompute per-thread event facts

A tiny value type built once per thread so rules read declaratively:

```swift
struct EventSummary {
    private let counts: [EventType: Int]
    private let ordered: [ExtractedEvent]   // stable-sorted by (timestamp, offset)

    func has(_ t: EventType) -> Bool          // presence
    func count(_ t: EventType) -> Int          // occurrences (for count rules)
    func sequence(_ s: [EventType]) -> Bool    // ordered subsequence (moved hasSequence here)
}
```

### (b) Data-driven rule table in the engine

Replace the hardcoded calls with a list the engine iterates:

```swift
struct AchievementRule {
    let id: String
    let summary: String
    let matches: (ParsedTranscript, EventSummary) -> Bool
}

static let rules: [AchievementRule] = [
    .init(id: "stack_trace_oracle", summary: "Shared a stack trace or raw error output.") {
        _, e in e.has(.stackTraceSeen)
    },
    .init(id: "one_more_run", summary: "Iterated fix → run → fail four or more times.") {
        _, e in e.count(.iterationTermSeen) >= 4
    },
    .init(id: "rubber_duck_with_a_gpu", summary: "Reasoned to a conclusion with no code change.") {
        _, e in e.sequence([.reasoningSeen, .conclusionSeen]) && !e.has(.codeChangeRequestSeen)
    },
    // …one line per achievement (existing 5 fold in here too)
]
```

`evaluate` becomes: build `EventSummary`, then for each rule whose contract is
`active && status == "keep" && !existingUnlockedIDs.contains(id)` and whose
`matches` returns true → `unlock`. The "first achievement" meta rule stays as its
special post-pass (needs to see whether any other unlock happened).

### (c) `KeywordRule` table in the extractor

Move the many keyword events into data instead of branches:

```swift
struct KeywordRule {
    let event: EventType
    let phrases: [String]
    let role: MessageRole?      // nil = any role
    let caseSensitive: Bool     // true only for capitalized error patterns
}
```

The extractor loops messages once, applies every `KeywordRule`, and keeps the few
genuinely special detectors (long-message metadata, first-user-turn gating for
corrections, co-occurrence emitters) as bespoke code.

---

## 3. New detectors (event types + keyword groups)

All lowercased substring matches unless noted. Word-ish boundary check (preceding
char not a letter) reused from the existing `mentionsAffirmativeSuccess` guard to
avoid matches inside larger identifiers.

| New `EventType` | Phrases (abridged) | Role |
|---|---|---|
| `creationRequestSeen` | intent (build / create / make / scaffold / generate / spin up) **and** target (app / tool / site / feature / component / script / plugin) co-occur in one message | user |
| `mvpLanguageSeen` | mvp, prototype, quick build, side project, weekend project, hackathon, poc, proof of concept | any |
| `contextLimitSeen` | context window, context limit, compaction, compacted, token limit, out of context, running out of context, summarize before | any |
| `tokenBudgetSeen` | tokens, cost, usage limit, rate limit, budget, context management, remaining context | any |
| `uncertainSuccessSeen` | "not sure why this works", "somehow it works", "somehow passing", "no idea why it works", "inexplicably" | any |
| `uncertaintySeen` | "i don't know why", "not sure why", "somehow this fixed", "unclear why", "beats me" | any |
| `doNotTouchSeen` | "don't touch", "leave it", "don't change", "no refactor", "stop here", "ship it as is" | any |
| `approvalLanguageSeen` | lgtm, looks good, ship it, approved, good to merge, ready to merge | any |
| `productionLanguageSeen` | production, deploy, in prod, real users, go live, launch it | any |
| `uiControlSeen` | button, modal, sidebar, dropdown, toggle, checkbox, settings panel, menu bar, tab | any |
| `cacheRitualSeen` | clear cache, restart server, reinstall, delete node_modules, clean build, remove dist, wipe cache | any |
| `shipLanguageSeen` | commit, pr, pull request, merge, release, deploy, publish, shipped, send it | any |
| `assistantPushbackSeen` | "i'd avoid", "i recommend against", "that's risky", "a safer approach", "instead i'd suggest", "i wouldn't" | **assistant** |
| `userTurnSeen` | emitted once per user message (enables "…then a later user turn") | user |
| `backgroundContextSeen` | for context, background, some history, to explain, the situation is | user |
| `reasoningSeen` | "let me think", "reasoning", "the tradeoff", "on one hand", "considering" | any |
| `conclusionSeen` | "so the answer", "conclusion", "therefore", "in that case i'd", "makes sense to" | any |
| `codeChangeRequestSeen` | edit, patch, apply, write the code, change the file, implement, refactor (any code-mutation intent) | any |
| `iterationTermSeen` | fix, run, retry, again, still failing, try once more, adjust (counted per occurrence) | any |
| `verificationFailureSeen` | failure term (fails / failing / red / broken) **near** verification term (test / build / lint / ci / suite) | any |
| `verificationSuccessSeen` | success term (passes / green / all pass) **near** verification term | any |
| `failureSeen` | broken, failing, doesn't work, stuck, error, blew up, crash (generic, not verification-scoped) | any |
| `styleAdjustmentSeen` | margin, padding, spacing, align, color, font, css, layout, pixel (counted per occurrence) | any |
| `frontendContextSeen` | css, ui, layout, component, styling, front end, tailwind, flexbox | any |

`prototypeLanguageSeen` reuses `mvpLanguageSeen`. Existing `successSeen`,
`stackTraceSeen` (expanded with `panic`, `fatal`, `Error:`, `exit code`),
`longMessageSeen`, and `oneMorePromptSeen` are reused as-is.

---

## 4. The 22 achievements — detection recipe

Grouped by engine mechanism. "Summary" is the notification trigger text.

### Presence (single event in thread)

| # | id | Rule | Notes |
|---|---|---|---|
| 4 | `prompt_it_into_existence` | `has(.creationRequestSeen)` | intent + target co-occur |
| 5 | `weekend_mvp_energy` | `has(.mvpLanguageSeen)` | |
| 13 | `the_message_had_mass` | `has(.longMessageSeen)` | already emitted ≥2000 chars |
| 15 | `context_window_sunset` | `has(.contextLimitSeen)` | |
| 16 | `token_budget_lifestyle` | `has(.tokenBudgetSeen)` | |
| 19 | `stack_trace_oracle` | `has(.stackTraceSeen)` | expand keyword list |
| 23 | `green_by_coincidence` | `has(.uncertainSuccessSeen)` | overlaps #24 — both may fire |
| 24 | `understanding_optional` | `has(.uncertaintySeen)` | |
| 32 | `lgtm_from_the_void` | `has(.approvalLanguageSeen)` | |
| 35 | `the_button_exists_now` | `has(.uiControlSeen)` | |
| 37 | `cache_clearing_ritual` | `has(.cacheRitualSeen)` | |
| 47 | `shipwright` | `has(.shipLanguageSeen)` | |

### Co-occurrence (two events present, unordered)

| # | id | Rule |
|---|---|---|
| 30 | `nobody_touch_it` | `has(.successSeen) && has(.doNotTouchSeen)` |
| 34 | `production_is_a_place` | `has(.mvpLanguageSeen) && has(.productionLanguageSeen)` |

### Count (≥ N occurrences)

| # | id | Rule |
|---|---|---|
| 21 | `one_more_run` | `count(.iterationTermSeen) >= 4` |
| 36 | `css_negotiations` | `has(.frontendContextSeen) && count(.styleAdjustmentSeen) >= 3` |

### Sequence (ordered)

| # | id | Rule |
|---|---|---|
| 17 | `the_app_has_opinions` | `sequence([.assistantPushbackSeen, .userTurnSeen])` |
| 18 | `lore_drop` | `sequence([.backgroundContextSeen, .codeChangeRequestSeen])` on a long user msg |
| 22 | `green_bar_acquired` | `sequence([.verificationFailureSeen, .verificationSuccessSeen])` |
| 25 | `we_are_so_back` | `sequence([.failureSeen, .successSeen])` |

### Sequence + metadata / negation

| # | id | Rule |
|---|---|---|
| 14 | `confidence_high_context_low` | `has(.longThread) && sequence([.contextLimitSeen, .userTurnSeen])` — a user turn continues *after* context-limit talk |
| 27 | `rubber_duck_with_a_gpu` | `sequence([.reasoningSeen, .conclusionSeen]) && !has(.codeChangeRequestSeen)` — reasoned, never touched code |

`longThread` = a thread-level flag when `userTurnCount >= LONG_THREAD_TURNS`
(default 8). Emitted like `longMessageSeen`/`oneMorePromptSeen` as a metadata
event, not a keyword.

---

## 5. False-positive / exclusion strategy

The contracts list exclusions like "term appears only in copied documentation or
error output" or "inside a source identifier." Honoring these perfectly is
expensive; the design spec explicitly favors cheap detection with tolerated
false positives. Best-effort measures:

- **Lowercasing + word-ish boundary** (preceding char not a letter) already
  prevents `unfixed`→`fixed` style matches. Reuse it for every keyword rule.
- **Role scoping** where it matters: corrections/lore/creation only count on user
  turns; assistant pushback only on assistant turns.
- **Negation guard** (existing 18-char preceding window for `not / no / never /
  cannot / n't`) reused for success-style phrases.
- **No code-block stripping.** `stack_trace_oracle` *wants* error output, so
  stripping fenced blocks would break it. We accept that error-related terms may
  occasionally fire from pasted logs — acceptable per spec.
- Once-per-user-ever identity means a single false positive unlocks at most one
  achievement, permanently — low blast radius, and the shelf shows what triggered
  it (`triggerSummary`).

---

## 6. Testing strategy

- **One positive fixture test per achievement** (contract requires ≥1 fixture per
  active contract). Small synthetic `ParsedTranscript`s exercising each rule.
- **Key negatives**: `#27` must NOT fire when a code change is present; `#25`/`#22`
  must NOT fire when success precedes failure (order matters); success phrases in
  larger words / negated contexts must NOT fire.
- **Count boundaries**: `#21` at 3 vs 4 iteration terms; `#36` at 2 vs 3 style
  terms.
- **Rule/contract coverage test**: assert every wired rule `id` exists in the
  bundled contracts (catch typos), and every Bucket-A contract id has a rule.
- Existing 49 tests must stay green; `EventSummary` gets direct unit tests for
  `has` / `count` / `sequence`.

---

## 7. Sequencing & rollout

1. Land the three refactors (§2) with the existing 5 achievements folded into the
   rule table — tests stay green, zero behavior change.
2. Add new `EventType`s + `KeywordRule` table entries (§3).
3. Add rules in small batches by mechanism (presence → co-occurrence → count →
   sequence → sequence+negation), testing each batch.
4. Bump `detectorFingerprintVersion` → `detectors-v3` (§1).
5. Run the app; confirm backfill re-indexes and posts one banner per newly wired
   achievement.

---

## 8. Open decisions

- **First-run notification burst.** With history cleared + 22 new achievements,
  the first authorized scan may post many banners at once. We agreed every
  achievement should notify (no grouped summary). Confirm we're fine with a
  potentially large first-run burst, or add a gentle pacing/delay between banners.
- **Thresholds** (all tunable defaults): `long_message ≥ 2000` chars,
  `iteration ≥ 4`, `style ≥ 3`, `long_thread ≥ 8` user turns.
- **Overlap achievements** (`#23`/`#24` uncertainty, `#5`/`#34` prototype terms)
  can both unlock from one thread — intended, not a bug.

---

## Deferred — Bucket B (19, not in scope here)

`local_legend`, `the_vibes_compiled`, `readme_driven_development`,
`the_first_big_door`, `side_quest_accepted`, `main_quest_never_heard_of_her`,
`keeper_of_small_fires`, `its_so_over`, `ship_it_before_it_notices`,
`multiclassing`, `party_finder`, `changed_lanes`, `co_op_campaign`,
`two_opinions_enter`, `model_diplomat`, `same_quest_different_campfire`,
`again_but_different`, `found_your_way_back`, `platinum_memory`.

These need a cross-transcript evaluation stage (querying the `threads` table for
counts, time windows, multi-tool/multi-model spans) that Bucket A deliberately
doesn't build.
