---
phase: 09-dashboard-polish
plan: 03
subsystem: dashboard / charts
tags:
  - ios26
  - swiftui
  - charts
  - appstorage
  - popover
  - legend
requirements:
  - CHART-01
  - CHART-02
dependency_graph:
  requires:
    - DropTimelineChart (existing aggregation, dropEvents/buckets/yMax)
    - SwiftUI @AppStorage
    - Charts framework (chartLegend modifier)
  provides:
    - Persistent silent/overt series filter (chartShowSilent / chartShowOvert)
    - Inline legend-as-filter chips with (i) info popover
    - Single discoverable surface (D-04)
  affects:
    - DashboardView Drop Timeline section (read-only — call site unchanged)
tech_stack:
  added: []
  patterns:
    - "@AppStorage Bool persistence (mirrors omitLocationData pattern)"
    - "Render-path filter (visibleBuckets) leaves aggregation pipeline intact (D-05)"
    - ".chartLegend(.hidden) to suppress Swift Charts auto-legend duplication"
key_files:
  created: []
  modified:
    - CellGuard/Views/DropTimelineChart.swift
decisions:
  - "Default both chips ON (D-06) — most truthful default, user opts in to silent-only"
  - "Toggled-off series hidden from chart input (D-05), not dimmed in-place"
  - "Off-chip visual treatment: opacity 0.4 (HIG de-emphasis)"
  - ".chartLegend(.hidden) is REQUIRED, not optional — implicit auto-legend would otherwise duplicate the chips"
metrics:
  duration: ~10min
  completed_date: "2026-04-25"
  tasks_completed: 2
  files_changed: 1
  commits: 1
---

# Phase 09 Plan 03: Timeline Chart Legend + Series Filter Summary

**One-liner:** Inline legend chips beneath the timeline chart double as a tap-to-toggle Silent/Overt series filter with an (i) popover explaining the distinction; persistent via @AppStorage and matching Apple Health/Fitness chart UX.

## What Shipped

`DropTimelineChart` now owns its own legend, filter, and explanatory popover — a single discoverable surface that replaces Swift Charts' implicit auto-legend. `DashboardView` is unchanged (its Drop Timeline caption was already title-only).

### New properties on `DropTimelineChart`

| Property | Kind | Purpose |
|----------|------|---------|
| `chartShowSilent` | `@AppStorage("chartShowSilent")` Bool, default `true` | Whether silent-failure bars are visible. Toggled by tapping the "Silent" chip. Persists across launches (D-07). |
| `chartShowOvert`  | `@AppStorage("chartShowOvert")` Bool, default `true`  | Whether overt path-change drop bars are visible. Toggled by tapping the "Overt" chip. Persists across launches (D-07). |
| `showInfoPopover` | `@State` Bool, default `false`                        | Drives the (i) info popover (D-02).                                                                                  |

The `@AppStorage` keys match the locked names from D-07 (`chartShowSilent`, `chartShowOvert`) — the pattern mirrors the existing `@AppStorage("omitLocationData")` in `DashboardView`.

### New computed property

```swift
private var visibleBuckets: [TimeBucket] {
    buckets.filter { bucket in
        switch bucket.type {
        case "Silent": return chartShowSilent
        case "Overt":  return chartShowOvert
        default:       return true
        }
    }
}
```

This is the entire render-path filter. `buckets`, `dropEvents`, and `yMax` are byte-for-byte unchanged so:
- aggregation logic stays intact for future analytics consumers (D-05),
- `yMax` keeps reading from `buckets` (not `visibleBuckets`) — the y-scale stays stable as the user toggles series, preventing chart-lurch.

### New view helpers

Three private helpers sit at the bottom of `DropTimelineChart` after `body` (under a `// MARK: - Legend & Info Popover` header):

- **`legendBar`** — `HStack(spacing: 12)` containing the two `legendChip(...)` instances, the `(i)` `Button` with `Image(systemName: "info.circle")`, and a trailing `Spacer(minLength: 0)`. The info button has `.popover(isPresented: $showInfoPopover, arrowEdge: .top)` attached, presenting `infoPopoverContent` inside `.padding(16).frame(maxWidth: 320).presentationCompactAdaptation(.popover)`.
- **`legendChip(label:color:isOn:action:)`** — Tappable Capsule chip: a small color-coded `Circle` (8pt) + `Text(label).font(.caption)` inside `padding(.horizontal, 10).padding(.vertical, 4)`, backgrounded by `Color(.tertiarySystemBackground)`, clipped to a `Capsule`, with `.opacity(isOn ? 1.0 : 0.4)` to mark off-state. Wraps a `Button(action: action)` with `.buttonStyle(.plain)` so the visual chip is the touch target. Carries `accessibilityLabel("\(label) drops")`, `accessibilityValue(isOn ? "Visible" : "Hidden")`, and `accessibilityHint("Double-tap to toggle \(label.lowercased()) drops")`.
- **`infoPopoverContent`** — `VStack(alignment: .leading, spacing: 12)` with: `Text("Drop Types").font(.headline)`, two definition rows (red/orange swatch + bold subheadline + secondary caption), a `Divider()`, `Text("Why this matters").font(.subheadline).bold()`, and the closing rationale paragraph.

### Locked copy (verbatim)

| Key | Value |
|-----|-------|
| Chip labels | `"Silent"`, `"Overt"` (D-03 vocabulary lock) |
| Popover heading | `"Drop Types"` |
| Silent definition | `"The modem reports it is connected, but the network probe failed — the "attached but unreachable" bug."` (curly quotes via `\u{201C}` / `\u{201D}`) |
| Overt definition | `"NWPathMonitor reported the connection went down — the system itself acknowledged the drop."` |
| Subheading | `"Why this matters"` |
| Rationale | `"Silent failures are the core evidence for the Apple Feedback Assistant report — they prove a modem-side fault that iOS itself does not report."` |
| Both-off hint | `"No series visible — tap a chip to enable"` |
| Empty-state copy | `"No drops in \(selectedWindow.rawValue)"` (preserved from prior behavior) |

### Rewritten `body` — three render branches

```
if dropEvents.isEmpty                       → "No drops in {window}" placeholder (preserved)
else if !chartShowSilent && !chartShowOvert → "No series visible — tap a chip to enable" hint (D-07 edge case)
else                                        → Chart(visibleBuckets) { … }
```

`legendBar` is inserted between the `Picker(...)` and the render branches. The Chart block has TWO required edits, with all other modifiers byte-for-byte identical:

1. `Chart(buckets)` → `Chart(visibleBuckets)`.
2. **`.chartLegend(.hidden)`** added between `.chartForegroundStyleScale([...])` and `.chartXScale(domain: chartDomain)`.

### Why `.chartLegend(.hidden)` is non-optional

Swift Charts auto-renders an implicit legend below the plot whenever `chartForegroundStyleScale` is set. Without `.chartLegend(.hidden)`, the user would see TWO legends — the custom chips above the chart AND the system-rendered legend below — directly contradicting D-04 ("the legend AND the filter are the same control — single discoverable surface"). Removing `.chartForegroundStyleScale(...)` is NOT an alternative because that scale is what colors the bars by series; the only correct suppression is `.chartLegend(.hidden)`.

This is now an explicit hard-gate acceptance criterion in the plan (was bumped from "secondary remediation" during plan revision).

## DashboardView confirmation

`DashboardView.swift` was inspected and is **unchanged** (zero-diff against base). The Drop Timeline section at lines 38–47 is already title-only:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Drop Timeline")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    DropTimelineChart(events: allEvents)
        .padding(.horizontal)
}
.padding(.bottom, 10)
```

Acceptance grep confirmed:
- `Text("Drop Timeline")` — 1 match.
- `DropTimelineChart(events: allEvents)` — 1 match (call-site contract preserved).
- No `chartShowSilent`/`chartShowOvert` references (the @AppStorage keys live exclusively inside `DropTimelineChart` — single discoverable surface, D-04).
- No inline legend HStack at the dashboard level.
- `@AppStorage("omitLocationData")` still present and unchanged (Phase 5/8 surface intact).

No edit was made because none was required. No empty commit was created.

## Untouched on purpose

These are byte-identical to before this plan and were verified by `git diff` / `grep`:

- `dropEvents` computed property (line 59) — D-05: filter affects the render path only.
- `buckets` aggregation (line 78) — same.
- `yMax` (line 152) — kept reading from `buckets` (not `visibleBuckets`) so y-scale stays stable as series toggle.
- `chartDomain`, `TimeWindow` enum, `selectedWindow` `@State` picker.
- `events: [ConnectivityEvent]` parameter on `DropTimelineChart` — call-site `DropTimelineChart(events: allEvents)` in `DashboardView` works unchanged.
- `CellGuard/Helpers/DropClassification.swift` — `git diff` empty, `isDropEvent` unaltered (drop classification is independent of render filtering).

## Tasks

| Task | Name                                                                                                                | Commit  | Files                                       |
| ---- | ------------------------------------------------------------------------------------------------------------------- | ------- | ------------------------------------------- |
| 1    | Add legend chips, popover, AppStorage filter, visibleBuckets render path, and chartLegend(.hidden) to DropTimelineChart | 7e3f07f | CellGuard/Views/DropTimelineChart.swift     |
| 2    | Verify DashboardView Drop Timeline section is title-only and does not duplicate legend rendering                      | (no-op) | CellGuard/Views/DashboardView.swift (zero diff) |

Task 2 was verification-only with the documented acceptable outcome of "no change" — no commit was created (the project disallows empty commits).

## Verification Notes

This is an iOS Swift / SwiftUI project (Xcode 26, iOS 26 target, free personal team signing).
`xcodebuild` cannot run from the CLI sandbox, so the automated `<verify>` block in the plan
(`xcrun xcodebuild ... build`) was NOT executed by this agent. Verification was instead performed via:

- File-content grep against every acceptance-criteria pattern from `<acceptance_criteria>` for both Tasks 1 and 2 — all passed.
- Static read-through of the rewritten `body` and helpers to confirm Swift compiles (`@AppStorage`, `@State`, `.popover`, `.chartLegend(.hidden)`, `presentationCompactAdaptation`, `Color(.tertiarySystemBackground)`, `\u{201C}`/`\u{201D}` escapes, accessibility modifiers — all are SwiftUI/Charts APIs already imported on lines 1–2).
- `git diff` confirmation that `DashboardView.swift` and `DropClassification.swift` are byte-identical to base.

The build gate plus the human UAT criteria (CHART-01, CHART-02, D-02, D-06, D-07, D-07 persistence) need to be exercised on the iPhone 17 Pro Max device by the user — they are out of reach from this CLI executor.

## Deviations from Plan

None — plan executed exactly as written. All `<interfaces>` snippets (A through E) inserted verbatim. Optional clean-ups suggested in the plan (`value in` → `_ in` in axis closures, moving `yMax` to read from `visibleBuckets`) were NOT applied because the plan explicitly marked them as "MAY" / "if Xcode does not warn" — the conservative path is to leave them.

## Known Stubs

None. The legend, filter, popover, and both-off hint are fully wired to live data via `@AppStorage` and `visibleBuckets`. No placeholder copy, no empty arrays flowing to UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- File `CellGuard/Views/DropTimelineChart.swift` exists and contains all required additions (verified via grep — see acceptance gate output above).
- File `CellGuard/Views/DashboardView.swift` exists and is byte-identical to base (verified via `git diff`).
- File `CellGuard/Helpers/DropClassification.swift` exists and is byte-identical to base (verified via `git diff`).
- Commit `7e3f07f` exists (`git log` confirmed via `git rev-parse --short HEAD` after commit).
- This SUMMARY.md exists at `.planning/phases/09-dashboard-polish/09-03-SUMMARY.md`.
- All acceptance grep checks for both Task 1 and Task 2 passed.

Build success and human UAT verification (CHART-01, CHART-02, D-02, D-06, D-07) require physical-device execution and are out of scope for this CLI executor — the user must run `xcrun xcodebuild` and the on-device UAT steps themselves.
