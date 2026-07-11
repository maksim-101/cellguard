---
phase: quick-260711-e5s
plan: 01
subsystem: connectivity-monitoring
tags: [drop-classification, throughput-gate, migration-safety, evidence-integrity]
dependency-graph:
  requires: [throughput-probe (260628-ope), health-score-option-h (260628-rpt)]
  provides: [severeLatency-drop-tier, referenceThroughputKbps-audit-field]
  affects: [DropClassification.isDropEvent, HealthScore.failureCounts, DropTimelineChart, AnalyticsView, SummaryReportView]
tech-stack:
  added: []
  patterns: ["Foundation-only pure rule type, machine-tested via standalone swiftc run"]
key-files:
  created:
    - CellGuard/Helpers/SevereLatencyRule.swift
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Helpers/DropClassification.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Helpers/HealthScore.swift
    - CellGuard/Views/DropTimelineChart.swift
    - CellGuard/Views/AnalyticsView.swift
    - CellGuard/Views/EventDetailView.swift
    - CellGuard/Views/SummaryReportView.swift
    - CellGuard/Models/SummaryReport.swift
decisions:
  - "Severe latency gated exclusively on measured throughput (no signal-strength inference, no private APIs) -- locked by user, D-01 in the plan."
  - "Missing or stale throughput reference is conservative (not severe) -- never claim what the data can't support."
  - "EventType.severeLatency uses explicit rawValue 12, following the migration-safety precedent of every prior case in this enum."
metrics:
  duration: ~50min
  completed: 2026-07-11
status: complete
---

# Phase quick-260711-e5s Plan 01: Severe-latency tier gated on throughput Summary

Adds a throughput-gated `.severeLatency` drop tier so a cellular probe that succeeds but takes
over 5 seconds is no longer silently counted as a clean success when the radio just proved it
could move data fast.

## What Was Built

**Task 1 — Pure rule + event type + drop classification** (commit `9cbf2a2`)
- `CellGuard/Helpers/SevereLatencyRule.swift` (new): a Foundation-only, dependency-free
  `SevereLatencyRule.isSevere(...)` function implementing the four-branch contract
  (slow+healthy → severe; slow+poor → not severe; slow+absent/stale → not severe;
  fast → not severe). No SwiftData/SwiftUI/ConnectivityEvent import, so the file compiles
  standalone and is machine-tested with a real `swiftc` run against production code.
- `EventType.severeLatency = 12` added to `ConnectivityEvent.swift` with doc comment,
  `encodingString`/`fromEncodingString`/`displayName`. New stored property
  `referenceThroughputKbps: Double?` (nil default) records the throughput reading the rule
  consulted, wired through `init`, `CodingKeys`, `encode(to:)` (outside the `omitLocation`
  privacy gate — it's a bandwidth number, no identity/location), and `init(from:)`.
- `DropClassification.isDropEvent()`: `.severeLatency` returns `true`.

**Task 2 — Apply the rule at capture time, keep counts consistent** (commit `0f0bc39`)
- `ConnectivityMonitor` retains `lastThroughput: (kbps: Double, at: Date)?` as monitor state,
  updated in `measureThroughput()` for **every** valid sample (healthy, slow, AND severe) —
  before the tier if/else — so a poor reading can suppress a severe-latency call and the rule
  can't become a one-way ratchet.
- `throughputFreshnessWindow` is a **derived** computed property
  (`throughputCycleInterval * probeInterval + probeInterval`), not a hardcoded constant.
- The rule runs only in the genuine `HTTP 200 + body contains "Success"` branch of `runProbe`,
  gated on `capturedPathUsesCellular` (the VPN-tolerant cellular gate, same one the throughput
  probe uses). It is explicitly **not** applied in the confirmation-host fluke branch (the
  `catch` path after `confirmSilentFailure()` returns false) — that branch's `latencyMs` times
  a failure, not a round-trip success, and a comment at that call site documents why.
  `referenceThroughputKbps` is recorded on **both** the drop and the not-a-drop outcome.
- `HealthScore.probeOutcomeTypes` (the score denominator) and the `stall` bucket in
  `failureCounts` both include `.severeLatency`; `DropTimelineChart`'s `.stall` series case and
  `AnalyticsView`'s stall-count filter were updated the same way, so the new drop type cannot
  silently vanish from either side of the drop ratio.

**Task 3 — Surface the audit trail + migration smoke test** (commit `a3af190`)
- `EventDetailView`'s Probe section now shows "Reference Throughput" when
  `referenceThroughputKbps` is present; legacy events (field nil) render exactly as before.
- `SummaryReportView`: the stall row, overview footer, and Drop Ratio popover numerator now say
  "Stalls (data / latency)" instead of "Data Stalls" (accurate now that severeLatency lands in
  the same bucket), and the footer states plainly that the rule is not retroactive.
- `SummaryReport.stallDrops` doc comment updated to name all three contributing event types
  (minor accuracy fix, not in the plan's file list but directly tied to this task).
- Migration smoke test executed against the existing populated iPhone 17 Pro Max simulator
  store (see Verification below).

## Deviations from Plan

None — plan executed as written. One out-of-scope-file touch: `CellGuard/Models/SummaryReport.swift`
line 8's doc comment was updated for accuracy (it said "severeThroughput" only; the bucket now
also includes `dataStall` and `severeLatency`). This is a comment-only change with no logic
impact — classified as in-scope accuracy correction (Rule 1/2 territory), not a deviation
requiring a decision.

## Verification

### Machine-verified by Claude

- **Four-branch + boundary test**, a real `swiftc` compile of `SevereLatencyRule.swift` plus a
  throwaway test harness (no test target, per project convention) — all 11 assertions passed:
  slow+healthy=drop, slow+poor=not-a-drop, slow+absent=not-a-drop, slow+stale=not-a-drop,
  fast=clean, threshold/healthy-bar boundary inclusivity, nil-latency handling.
- `.severeLatency` rawValue 12, encodes/decodes/displays, returns `true` from `isDropEvent`.
- Simulator build (`iPhone 17 Pro Max` destination) — BUILD SUCCEEDED, three times (once per
  task, catching regressions early).
- Device build (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`) — BUILD SUCCEEDED.
- Grep-verified wiring: rule invoked at capture time on the cellular-gated path; freshness
  window derived from `throughputCycleInterval` × `probeInterval` (not hardcoded); healthy bar
  sourced from the existing `slowThroughputThresholdKbps` constant (no duplicated literal);
  `.severeLatency` present in `HealthScore`, `DropTimelineChart`, and `AnalyticsView`.
- **Migration smoke test** against the real, populated iPhone 17 Pro Max simulator store
  (bundle `com.moritz.cellguard.app`, continuously growing store dating back to 2026-06-29):
  - Backed up `default.store`/`-wal`/`-shm` to scratchpad before installing the new build.
  - Pre-migration: 86 rows, 0 rows with `ZEVENTTYPERAW = 12`.
  - Installed the new build **over the existing container** (no erase, no uninstall — confirmed
    via matching earliest-timestamp `2026-06-29 06:22:45` before and after).
  - Post-migration: row count grew monotonically across the test (86 → 91, all new heartbeat
    events from live monitoring during the test — zero rows lost).
  - `PRAGMA table_info` confirms `ZREFERENCETHROUGHPUTKBPS` is now present — proving lightweight
    migration actually ran, not a silently recreated store.
  - `ZEVENTTYPERAW = 12` count stayed **0** throughout — no historical row was reclassified
    (D-07 confirmed).
  - No `134110` in the device log (`log show --predicate 'process == "CellGuard"'`).
  - App stayed alive across three relaunches (verified via `launchctl list` and an absence of
    new entries in `~/Library/Logs/DiagnosticReports`).

### NOT verified by Claude — requires the physical iPhone 17 Pro Max on cellular

- **End-to-end field firing.** The simulator has no cellular path, so `capturedPathUsesCellular`
  is always false there and `lastThroughput` never populates — the rule always takes the
  conservative no-data branch on simulator. The pure logic is proven; the plumbing that feeds it
  real throughput numbers is not exercised end-to-end in this session.
- **Real slow-probe episodes classified correctly**, and the load-bearing negative: that
  genuinely weak-signal locations do **not** produce `.severeLatency` events. Both require the
  physical device on cellular and are the subject of the blocking checkpoint.
- **UI screenshot of an event detail / Summary Report view.** Attempted via simulator
  screenshot + macOS accessibility-driven tap automation (`osascript`/System Events); the
  attempt was blocked by an unrelated fullscreen Safari window capturing all click input in this
  environment, and I stopped rather than risk disrupting the user's Safari session. The home
  screen screenshot confirms the app launches cleanly post-migration and shows a growing event
  count with no visible layout break, but I could not capture the Probe section or Summary
  Report screens directly. This is listed as a `<human-check>` item in the plan already, so it
  rolls into the blocking checkpoint below rather than blocking this task.

Built, not yet verified: the on-device end-to-end path (items above). Everything else in the
`<verification>` block of the plan is machine-verified as described.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary schema changes. The new
`referenceThroughputKbps` field is a bandwidth number with no identity/location content, and it
is exported alongside existing non-gated fields following the same reasoning as
`radioServices`.

## Self-Check: PASSED

- `CellGuard/Helpers/SevereLatencyRule.swift` — FOUND
- `CellGuard/Models/ConnectivityEvent.swift` — FOUND (modified, `severeLatency` present)
- `CellGuard/Helpers/DropClassification.swift` — FOUND (modified)
- `CellGuard/Services/ConnectivityMonitor.swift` — FOUND (modified)
- `CellGuard/Helpers/HealthScore.swift` — FOUND (modified)
- `CellGuard/Views/DropTimelineChart.swift` — FOUND (modified)
- `CellGuard/Views/AnalyticsView.swift` — FOUND (modified)
- `CellGuard/Views/EventDetailView.swift` — FOUND (modified)
- `CellGuard/Views/SummaryReportView.swift` — FOUND (modified)
- `CellGuard/Models/SummaryReport.swift` — FOUND (modified, comment fix)
- Commit `9cbf2a2` — FOUND in `git log`
- Commit `0f0bc39` — FOUND in `git log`
- Commit `a3af190` — FOUND in `git log`
- `CellGuard.xcodeproj/project.pbxproj` diff unchanged by this task (still only the
  pre-existing signing-related 4-line diff from session start) — CONFIRMED
