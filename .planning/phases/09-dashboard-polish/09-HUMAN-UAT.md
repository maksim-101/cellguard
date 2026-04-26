---
status: failed
phase: 09-dashboard-polish
source: [09-VERIFICATION.md]
started: 2026-04-25T00:00:00Z
updated: 2026-04-26T00:00:00Z
---

## Current Test

Device UAT complete (2026-04-26). 3 visual gaps confirmed → Phase 9.1 gap closure. 4 items observed passing on-device; 3 items not yet exercised but not currently failing.

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
result: passed (chips and (i) button visible per screenshot 1; no duplicate auto-legend)

### 5. CHART-02 — toggle-off filter actually hides series + AppStorage persists
expected: Tap 'Overt' chip → orange bars disappear, only red (silent) bars remain. Tap 'Overt' again → bars return. Then tap BOTH chips off → chart area shows 'No series visible — tap a chip to enable' (D-07). Force-quit and relaunch — the last chip state must persist (AppStorage).
result: pending (not exercised in this UAT pass — re-test after gap closure rebuild)

### 6. CHART-01 — popover anchors to (i) button and shows correct copy
expected: Tap (i) → SwiftUI .popover (NOT a sheet) appears anchored to the button. Heading reads 'Drop Types'. Two definition rows (Silent — '"attached but unreachable" bug', Overt — 'NWPathMonitor reported the connection went down'). Below a Divider, the 'Why this matters' subhead is followed by the Apple-Feedback-Assistant rationale line.
result: failed → see G1. Popover anchors correctly and copy is present in source, but the popover container truncates BOTH definition rows ('The modem reports it is connected,…' / 'NWPathMonitor reported the conne…') AND clips the 'Why this matters' paragraph mid-sentence. Sizing/wrapping defect.

### 7. CHART-03 — dashboard updates within 1 second of a logged event
expected: Foreground app on dashboard view. Wait for (or trigger) a real .silentFailure or .probeFailure. The 'Drops (24h)' card and timeline chart MUST update without scrolling, tapping, or backgrounding — visible delay under 1 second.
result: pending (not exercised in this UAT pass — re-test after gap closure rebuild)

### G1. CHART-01 popover truncation (NEW — device-discovered)
expected: Popover content fully readable; both definition rows wrap; "Why this matters" paragraph completes.
result: failed → fix in 9.1.

### G2. POLISH-01 'Last Background Wake' row clipping (NEW — device-discovered)
expected: Row text fully readable inside the HealthDetailSheet; sheet detent or layout accommodates the multi-line "Never (no background wake yet)" / "Xs ago" string.
result: failed → fix in 9.1.

### G3. Drop Timeline 6h view axis truncation (NEW — device-discovered)
expected: X-axis labels readable in the 6h zoom (matches 24h/7d readability).
result: failed → fix in 9.1.

## Summary

total: 10
passed: 1
issues: 3
pending: 6
skipped: 0
blocked: 0

## Gaps

- G1 — popover truncation (CHART-01) → planned for Phase 9.1
- G2 — wake row clipping (POLISH-01) → planned for Phase 9.1
- G3 — 6h axis truncation (CHART-01/02 polish) → planned for Phase 9.1
