---
phase: 09-dashboard-polish
plan: 01
subsystem: connectivity-monitor
tags:
  - ios26
  - swift
  - probe
  - dedup
  - observable
  - swiftdata
  - polish-02
  - chart-03
requires:
  - ConnectivityMonitor (existing @MainActor service)
  - EventType.probeSuccess / .probeFailure / .silentFailure (existing)
  - EventStore.insertEvent synchronous save (verified pre-existing)
provides:
  - "ConnectivityMonitor.lastProbeStartedAt: Date? (private)"
  - "ConnectivityMonitor.lastProbeOutcome: EventType? (private)"
  - "Probe deduplication: sliding 60s window, success-only suppression"
affects:
  - CellGuard/Services/ConnectivityMonitor.swift (modified)
tech-stack:
  added: []
  patterns:
    - "Sliding-window dedup at probe-firing layer (not chart/aggregation layer)"
    - "Probe-START clock + post-resolve outcome assignment, both @MainActor-isolated"
key-files:
  created: []
  modified:
    - CellGuard/Services/ConnectivityMonitor.swift
decisions:
  - "Sliding 60s window via Date().timeIntervalSince(started) < 60 (D-13 — avoids calendar-minute boundary edge case)"
  - "Suppression filter is exactly lastProbeOutcome == .probeSuccess (D-14 — failures are evidence, never suppressed)"
  - "Probe-START clock updated BEFORE await so concurrent callers are also blocked (D-15)"
  - "Outcome written AFTER each logEvent at all four sites (success, HTTP-non-200, silentFailure, catch-else)"
  - "EventStore.swift NOT modified — verified pre-existing try modelContext.save() at EventStore.swift:26 satisfies CHART-03"
  - "runSingleProbe() and startProbeTimer() not modified — they inherit dedup via runProbe()"
metrics:
  duration: ~5min
  completed: 2026-04-25
requirements_completed:
  - POLISH-02
  - CHART-03
---

# Phase 9 Plan 1: ConnectivityMonitor Probe Dedup + CHART-03 Verification Summary

**One-liner:** Probe deduplication on ConnectivityMonitor — sliding 60s window suppresses only `.probeSuccess` (failures always log); CHART-03 satisfied by verified pre-existing synchronous `try modelContext.save()` in `EventStore.insertEvent` (no edit needed).

## What Changed

### CellGuard/Services/ConnectivityMonitor.swift

Two new private instance properties, one dedup guard, and four outcome assignments. Net addition: 29 lines.

#### Properties (lines 78–89)

Added in the "Internal State for Classification" block, immediately after `vpnReassertingUntil`:

```swift
/// Wall-clock timestamp of the most recent probe START. ...
private var lastProbeStartedAt: Date?

/// Outcome of the most recent fully resolved probe. ...
private var lastProbeOutcome: EventType?
```

#### Dedup guard (lines 277–289)

Inserted at the TOP of `runProbe()`, BEFORE the existing `let capturedStatus = currentPathStatus` capture block:

```swift
@MainActor
private func runProbe() async {
    // POLISH-02 dedup guard (D-11..D-15): suppress only redundant successes within a
    // sliding 60s window. Failures (.probeFailure, .silentFailure) NEVER short-circuit
    // the next probe — every failure-state moment deserves fresh confirmation.
    if let started = lastProbeStartedAt,
       Date().timeIntervalSince(started) < 60,
       lastProbeOutcome == .probeSuccess {
        return
    }
    // Update probe-START clock BEFORE the await so a concurrent caller is also blocked
    // by the same window. Outcome is set AFTER each logEvent below.
    lastProbeStartedAt = Date()

    // Pitfall 5: Capture state before awaiting probe to avoid race condition
    let capturedStatus = currentPathStatus
    ...
```

#### Four `lastProbeOutcome` assignments

Each one immediately follows its sibling `logEvent(...)` call. The literal `EventType` case matches what was just logged.

| # | Branch                                      | logEvent line | Outcome assignment line |
| - | ------------------------------------------- | ------------- | ----------------------- |
| 1 | Success branch (HTTP 200)                   | 307           | 315 (`= .probeSuccess`) |
| 2 | HTTP-non-200 (still inside `do`)            | 319           | 328 (`= .probeFailure`) |
| 3 | Catch / silentFailure (after `dropStartDate` write) | 349   | 362 (`= .silentFailure`)|
| 4 | Catch / probeFailure (else branch)          | 365           | 374 (`= .probeFailure`) |

The `silentFailure` outcome assignment is intentionally placed AFTER the existing `if dropStartDate == nil { dropStartDate = Date() }` write so the existing pattern is preserved.

## CHART-03 disposition

**Verified — no edit needed.** The investigation (Task 2) confirmed:

1. `EventStore.insertEvent` calls `try modelContext.save()` synchronously at `CellGuard/Services/EventStore.swift:26`.
2. `git diff --stat CellGuard/Services/EventStore.swift` returns empty — file is byte-identical to its pre-plan state, honoring the plan's `files_modified` contract.
3. `DashboardView` consumes events via `@Query(sort: \ConnectivityEvent.timestamp, order: .reverse)`, which propagates synchronous SwiftData saves to view consumers within tens of milliseconds — well inside the 1-second budget.

Combined with the new probe dedup eliminating duplicate `.probeSuccess` rows, CHART-03 ("dashboard updates within 1s of any logged event") is satisfied by the existing reactivity. **No `processPendingChanges`, `@Observable` event-count signal, or `objectWillChange` trigger was introduced.**

## What Was Intentionally NOT Touched

- **`CellGuard/Services/EventStore.swift`** — byte-identical to pre-plan state. Task 2 was strictly verification-only; the plan's `files_modified` is scoped to ConnectivityMonitor.swift alone.
- **`runSingleProbe()`** (line 250) — already calls `runProbe()` and inherits dedup automatically.
- **`startProbeTimer()`** (line 227) — the 5-second initial-delay launch task at lines 234–237 calls `runProbe()` and inherits dedup. The timer itself fires `runProbe()` via `Task { ... }` and inherits dedup.
- **`processPathChange()`** path-change classification — orthogonal to the probe pipeline; dedup applies only to probe-firing layer.
- **`logEvent()`** — unchanged; outcome assignment lives in `runProbe()` at the call sites, not inside `logEvent`, so non-probe events (path changes, restorations, gaps) never touch `lastProbeOutcome`.

## Interface Contract for Plan 09-02 / 09-03

**None.** This plan exposes no new public surface — it tightens existing behavior. The two new properties are `private` and have no external consumers.

## Verification

### Automated grep checks (all PASSED)

| Check | Result |
| ----- | ------ |
| `var lastProbeStartedAt: Date?` exists once | PASS (line 83) |
| `var lastProbeOutcome: EventType?` exists once | PASS (line 89) |
| `Date().timeIntervalSince(started) < 60` exists once | PASS (line 282) |
| `lastProbeOutcome == .probeSuccess` exists once | PASS (line 283) |
| `lastProbeStartedAt = Date()` exists once | PASS (line 288) |
| `lastProbeOutcome = .probeSuccess` exists once | PASS (line 315) |
| `lastProbeOutcome = .probeFailure` exists exactly twice | PASS (lines 328, 374) |
| `lastProbeOutcome = .silentFailure` exists once | PASS (line 362) |
| No `calendar-minute` / `startOfHour` / `truncatingRemainder.*60` anti-patterns | PASS |
| Dedup guard precedes `let capturedStatus = currentPathStatus` | PASS (`awk` count = 2) |
| `EventStore.swift` byte-identical (`git diff --stat`) | PASS (empty diff) |
| `try modelContext.save()` present in EventStore.swift | PASS (line 26 inside `insertEvent`) |
| No `processPendingChanges` introduced anywhere | PASS |
| No new `@Observable` scaffolding in EventStore | PASS |

### Build verification

This is an iOS Swift / SwiftUI project (Xcode 26, iOS 26 target). Full `xcodebuild` is unavailable in this CLI sandbox. As a substitute, `xcrun swiftc -parse -target arm64-apple-ios26.0-simulator CellGuard/Services/ConnectivityMonitor.swift` was run and parsed cleanly (only a benign sysroot/target warning). The orchestrator / human-driven Xcode build is the authoritative compile gate after merge.

### Manual UAT (deferred to device — for the human runner)

- **POLISH-02:** With app foregrounded, exit to home screen and re-enter within 30 seconds. Verify the event log contains at most ONE `.probeSuccess` row inside that minute window. The redundant probe at the wake should be suppressed by the dedup guard.
- **POLISH-02 (failure not suppressed):** With Wi-Fi/cellular intentionally broken (e.g. Airplane Mode mid-probe), verify the failure (`.probeFailure` or `.silentFailure`) is logged on the next probe even if it is < 60s after the prior one — failures must NEVER short-circuit.
- **CHART-03:** With the app foregrounded and a Wi-Fi connection that occasionally drops, leave the dashboard visible. When a `.silentFailure` is logged (visible in event log), the "Drops (24h)" card and timeline chart MUST update without scrolling, tapping, or backgrounding. Visible delay should be under 1 second.

## Deviations from Plan

None — plan executed exactly as written. Edits A, B, and C in `<interfaces>` matched the file as expected (lines shifted slightly from the planning estimate because the property block ended at line 76 in the plan vs after line 76 in the actual file, and `runProbe()`'s body started at line 264). The grep-anchored placement strategy from the plan handled this without issue.

## Authentication Gates

None.

## Known Stubs

None — no placeholder UI strings, no empty-array data sources, no TODO markers added. The change is purely behavioral on an already-wired pipeline.

## Self-Check

### Files
- `CellGuard/Services/ConnectivityMonitor.swift`: FOUND (modified, +29 lines)
- `CellGuard/Services/EventStore.swift`: FOUND (byte-identical — 0 lines changed)

### Commits
- `e5caf61` `feat(09-01): probe dedup guard in ConnectivityMonitor`: FOUND

### Acceptance criteria
- All 14 grep checks: PASS
- Both invariants documented in CHART-03 disposition: PASS

## Self-Check: PASSED
