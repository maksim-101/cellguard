---
phase: quick-260628-ope
plan: "01"
subsystem: connectivity-monitoring
tags: [throughput, cellular, slow-data, event-model, ui]
status: complete

dependency_graph:
  requires: []
  provides: [throughputKbps-field, slowThroughput-event-type, throughput-probe, throughput-ui-row]
  affects: [ConnectivityEvent, ConnectivityMonitor, EventDetailView]

tech_stack:
  added: []
  patterns: [wake-then-probe-piggyback, encodeIfPresent-mirror, exhaustive-switch-compile-gate]

key_files:
  created: []
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift

decisions:
  - "Throughput probe endpoint: speed.cloudflare.com/__down?bytes=102400 (100 KB, Cloudflare already trusted host)"
  - "Scheduling: every 5th 60s cycle (≈5 min), cellular only, after probeSuccess — foreground-only, no background probing"
  - "Threshold: 1000 Kbps (1 Mbps) for .slowThroughput; at/above logs .probeSuccess with throughputKbps attached"
  - "Dedup bypass: measureThroughput calls logEvent directly, never sets lastProbeOutcome/lastProbeStartedAt"
  - "Data budget: ~100 KB × ~12/hr × 24h ≈ 29 MB/day on cellular"

metrics:
  duration: "~10 min"
  completed: "2026-06-28"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 3
---

# Phase quick-260628-ope Plan 01: Cellular Throughput Probe Summary

**One-liner:** 100 KB Cloudflare download probe every ~5 min on cellular, logging `throughputKbps` and a new `.slowThroughput = 7` event type to catch bandwidth collapses invisible to the existing reachability probe.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add throughputKbps field and .slowThroughput event type | ec7258c | ConnectivityEvent.swift |
| 2 | Add throughput measurement and schedule on probe cycle | 1341698 | ConnectivityMonitor.swift |
| 3 | Surface throughput in detail UI, confirm notification exclusion, build-verify | 2f2c68b | EventDetailView.swift |

## What Was Built

**ConnectivityEvent.swift**
- `EventType.slowThroughput = 7` (explicit rawValue for migration safety), wired into `encodingString`, `fromEncodingString`, `displayName` — all exhaustive switches, compile gate enforces correctness
- `var throughputKbps: Double?` optional stored property, threaded through `init` (default nil), `CodingKeys`, `encodeIfPresent` (outside `omitLocation` block — not location data), and `decodeIfPresent` — mirrors `probeLatencyMs` exactly; SwiftData treats new optional as lightweight migration, no migration code needed

**ConnectivityMonitor.swift**
- Four tunable probe members: `throughputProbeURL` (Cloudflare `__down?bytes=102400`), `throughputCycleInterval = 5`, `slowThroughputThresholdKbps: Double = 1000`, `throughputCycleCounter = 0`
- `measureThroughput(...)` — fresh ephemeral session per measurement (reuses `makeProbeSession()`), `defer { session.finishTasksAndInvalidate() }`, guards divide-by-zero (elapsed > 0.001s) and non-200 responses, computes `kbps = (data.count * 8.0) / 1000.0 / elapsed`, logs `.slowThroughput` or `.probeSuccess` with `throughputKbps:` — calls `logEvent` directly, never touches `lastProbeOutcome`/`lastProbeStartedAt`
- `logEvent` gains `throughputKbps: Double? = nil` parameter, threaded into `ConnectivityEvent` init
- Scheduling gate at end of `runProbe()`: `throughputCycleCounter += 1; if ... % 5 == 0 && cellular && probeSuccess { await measureThroughput(...) }`

**EventDetailView.swift**
- Conditional `LabeledContent("Throughput", ...)` in `Section("Cellular")` showing `kbps / 1000` formatted as `"%.1f Mbps"` — appears only when `event.throughputKbps != nil`

## Verification Evidence

```
** BUILD SUCCEEDED **
```
Build command: `xcodebuild build -project CellGuard.xcodeproj -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO`

grep confirms:
- `case slowThroughput = 7` ✓
- `var throughputKbps: Double?` ✓
- `encodeIfPresent(throughputKbps` ✓
- `Slow Throughput` (displayName) ✓
- `func measureThroughput` ✓
- `__down` (endpoint) ✓
- `throughputCycleCounter` ✓
- `slowThroughputThresholdKbps` ✓
- `Throughput` row in EventDetailView ✓

## Notification and Drop Exclusion (Confirmed, No Edit Needed)

`scheduleDropNotification` guard: `guard eventType == .silentFailure || (eventType == .pathChange && (currentPathStatus == .unsatisfied || currentPathStatus == .requiresConnection))` — `.slowThroughput` excluded for free, same as `.vpnStateChange`.

`isDropEvent` in DropClassification.swift: has a `default` branch returning `false` — `.slowThroughput` is correctly not a drop.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

No new trust boundaries beyond those in the plan's threat model. `throughputProbeURL` is the only new egress point; documented as T-ope-01 (accepted) in PLAN.md.

## Self-Check

**Commits exist:**
- ec7258c: feat(quick-260628-ope-01): add throughputKbps field and .slowThroughput event type ✓
- 1341698: feat(quick-260628-ope-01): add cellular throughput probe to ConnectivityMonitor ✓
- 2f2c68b: feat(quick-260628-ope-01): surface throughputKbps as Mbps in EventDetailView Cellular section ✓

**Files exist:**
- CellGuard/Models/ConnectivityEvent.swift ✓
- CellGuard/Services/ConnectivityMonitor.swift ✓
- CellGuard/Views/EventDetailView.swift ✓

## Self-Check: PASSED
