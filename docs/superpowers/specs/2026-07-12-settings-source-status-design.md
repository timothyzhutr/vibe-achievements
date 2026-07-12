# Settings Source Status Design

## Goal

Make every source row answer two separate questions at a glance:

1. Is this source enabled by the user?
2. Did the latest scan connect to it successfully?

## Presentation

Use an explicit two-state layout inside each existing source row. Keep the
source name and description first, followed by two compact labeled fields:

- **Enabled** contains the existing switch and its On/Off state.
- **Connection** contains a small status symbol, label, and conversation count
  when applicable.

The folder path and Choose/Reset controls remain below these fields. No new
cards or nested panels are introduced.

Connection labels are:

- `Refreshing` before the first scan result;
- `Connected · N conversations` for indexed history;
- `No conversations` when the source is reachable but empty;
- `Needs attention` when discovery or parsing produced warnings;
- `Unavailable` when the configured source location cannot be found;
- `Disabled` when the source toggle is off.

Use green only for Connected, amber for Needs attention, red for Unavailable,
and secondary text for Refreshing, No conversations, and Disabled. Status must
also be communicated in text and accessibility labels, never color alone.

## State And Data Flow

`AppState` publishes a dictionary keyed by `SourceTool`. Each successful scan
stores the complete ordered status result already produced by
`ConversationSourceRegistry` and `Indexer`. Settings rows read their matching
status from that dictionary.

Toggling a source keeps the current behavior: persist settings and trigger a
rescan. The row immediately renders `Disabled` when off. When turned on, it
renders `Refreshing` until the rescan supplies a connection state.

The UI does not probe folders or databases itself. Discovery remains owned by
the source adapters, preventing settings and indexing from disagreeing.

## Failure Behavior

If the overall scan fails, enabled sources receive their existing failure
statuses and show `Needs attention` or `Unavailable`. A source without a status
shows `Refreshing`; absence is not interpreted as success.

Existing top-level source and warning summaries remain for this iteration.
Individual warning details and remediation actions are outside this scope.

## Testing

- App-state tests verify scan results publish per-source statuses.
- Presentation-model tests cover every connection state, counts, disabled
  override, and refreshing fallback.
- Existing source settings persistence and scan tests remain green.
- Manual macOS verification covers enabled/disabled toggles, status colors,
  long paths, and the five-source layout at the current window size.
