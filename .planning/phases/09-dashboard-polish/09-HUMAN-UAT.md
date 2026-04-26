---
status: partial
phase: 09-dashboard-polish
source: [09-VERIFICATION.md]
started: 2026-04-25T00:00:00Z
updated: 2026-04-25T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. POLISH-02 — successes dedup but failures never do
expected: Foreground app, exit to home, return within 30s. Open event log: at most ONE .probeSuccess row in the same minute window. Then put the device into Airplane Mode mid-probe — the .silentFailure / .probeFailure on the next probe MUST be logged even if it's <60s since the prior probe.
result: [pending]

### 2. POLISH-01 — TimelineView ticks at 1 Hz on iPhone 17 Pro Max
expected: Open HealthDetailSheet via the health-bar tap. If a background wake has occurred since install, the 'Last Background Wake' relative-time text re-renders at least once per second (e.g. '12 sec ago' → '13 sec ago'). If no wake has occurred yet, the row reads exactly 'Never (no background wake yet)'.
result: [pending]

### 3. POLISH-01 — applicationState gate writes only on background wakes
expected: Trigger a 500m significant location change while the app is BACKGROUND-ed (force-quit briefly is fine — sigChange relaunches it). Re-open the sheet — the wake timestamp must update. Conversely, with the app FOREGROUNDED, a foreground location callback must NOT update the timestamp (the row's relative-time should keep counting up from the prior background wake).
result: [pending]

### 4. CHART-01 — legend chips visible AND no duplicate Charts auto-legend
expected: Scroll to 'Drop Timeline'. Two color-coded chips ('Silent' red, 'Overt' orange) render beneath the segmented Picker, alongside an (i) info button. NO second legend renders below the chart plot (the implicit Charts auto-legend must be suppressed by .chartLegend(.hidden)).
result: [pending]

### 5. CHART-02 — toggle-off filter actually hides series + AppStorage persists
expected: Tap 'Overt' chip → orange bars disappear, only red (silent) bars remain. Tap 'Overt' again → bars return. Then tap BOTH chips off → chart area shows 'No series visible — tap a chip to enable' (D-07). Force-quit and relaunch — the last chip state must persist (AppStorage).
result: [pending]

### 6. CHART-01 — popover anchors to (i) button and shows correct copy
expected: Tap (i) → SwiftUI .popover (NOT a sheet) appears anchored to the button. Heading reads 'Drop Types'. Two definition rows (Silent — '"attached but unreachable" bug', Overt — 'NWPathMonitor reported the connection went down'). Below a Divider, the 'Why this matters' subhead is followed by the Apple-Feedback-Assistant rationale line.
result: [pending]

### 7. CHART-03 — dashboard updates within 1 second of a logged event
expected: Foreground app on dashboard view. Wait for (or trigger) a real .silentFailure or .probeFailure. The 'Drops (24h)' card and timeline chart MUST update without scrolling, tapping, or backgrounding — visible delay under 1 second.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
