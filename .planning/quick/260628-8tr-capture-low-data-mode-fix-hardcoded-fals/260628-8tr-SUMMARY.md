---
phase: 260628-8tr
plan: "01"
subsystem: connectivity-monitoring
tags: [bug-fix, data-fidelity, low-power-mode, low-data-mode, model, ui]
status: complete

dependency_graph:
  requires: []
  provides:
    - lowPowerMode field on ConnectivityEvent (model + Codable)
    - live isExpensive/isConstrained on probe-path events (bug fix)
    - Low Power Mode row in EventDetailView
  affects:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift

tech_stack:
  added: []
  patterns:
    - Pitfall 5 before-await capture (existing pattern extended)
    - decodeIfPresent ?? false for migration-safe Codable decode

key_files:
  created: []
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift

decisions:
  - "Used decodeIfPresent ?? false for lowPowerMode decode (not the non-optional decode used by isConstrained) so legacy export JSON files lacking the key still decode cleanly"
  - "On/Off vocabulary for Low Power Mode row (not Yes/No) to match system Settings UI language"
  - "No SwiftData migration written — additive non-optional Bool with default is lightweight-migration-safe"

metrics:
  duration: ~10 minutes
  completed: 2026-06-28
---

# Phase 260628-8tr Plan 01: Capture Low Data Mode Fix + lowPowerMode Summary

**One-liner:** Fixed probe-path events always misrecording Low Data Mode as OFF (hardcoded `false`), and added per-event `lowPowerMode: Bool` field across model, monitor, and detail UI.

## Tasks Completed

| # | Task | Commit | Key files |
|---|------|--------|-----------|
| 1 | Add `lowPowerMode` to ConnectivityEvent (model + Codable) | `9056ec3` | ConnectivityEvent.swift |
| 2 | Capture live flags in ConnectivityMonitor — fix bug + thread lowPowerMode | `1574f9e` | ConnectivityMonitor.swift |
| 3 | Surface Low Power Mode in EventDetailView + build verify | `880d680` | EventDetailView.swift |

## What Was Built

### Bug Fix (Task 2)
All 6 probe-path `logEvent` calls in `runProbe()` previously hardcoded `isExpensive: false, isConstrained: false`. This meant every `silentFailure`, `probeFailure`, and `probeSuccess` event — the core evidence signal — always showed Low Data Mode as OFF regardless of the real system state.

Fixed by adding three before-await snapshots alongside the existing `capturedPathUsesCellular` (Pitfall 5 pattern):
- `capturedIsExpensive = pathMonitor.currentPath.isExpensive`
- `capturedIsConstrained = pathMonitor.currentPath.isConstrained`
- `capturedLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled`

All 6 probe-path `logEvent` calls now pass the captured live values.

### New Field (Tasks 1, 2, 3)
`lowPowerMode: Bool` added end-to-end:
- **Model**: stored property + init param (`= false`) + CodingKeys case + unconditional encode + `decodeIfPresent ?? false` decode
- **Monitor**: `logEvent()` parameter threaded to `ConnectivityEvent` init; `processPathChange()` parameter threaded to its 4 `logEvent` calls; `handlePathUpdate` reads `ProcessInfo.processInfo.isLowPowerModeEnabled` and passes it to vpnStateChange event + debounced processPathChange call
- **UI**: `LabeledContent("Low Power Mode", value: event.lowPowerMode ? "On" : "Off")` in the Network section of EventDetailView

### Export Coverage
JSON export is automatically covered by the `encode(to:)` change (unconditional encode, not location-gated). No CSV path exists in this codebase.

## Deviations from Plan

None — plan executed exactly as written. The `logEvent` default parameter (`lowPowerMode: Bool = false`) handles the vpnStateChange call from `handlePathUpdate` which now explicitly passes the live value, so no call site was left without the real value.

## Build Evidence

```
** BUILD SUCCEEDED **
```

Built with:
```
xcodebuild -project CellGuard.xcodeproj -scheme CellGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build CODE_SIGNING_ALLOWED=NO
```

Warnings present are pre-existing CLGeocoder deprecations in AnalyticsView.swift (iOS 26 SDK), unrelated to this change.

## Self-Check

- [x] ConnectivityEvent.swift: `lowPowerMode` in stored property, init, CodingKeys, encode, decode — 6 occurrences confirmed
- [x] ConnectivityMonitor.swift: 0 remaining `isExpensive: false` in non-comment code; 7 occurrences of `capturedLowPowerMode` (1 declaration + 6 call sites)
- [x] EventDetailView.swift: `"Low Power Mode"` row present
- [x] Commits: `9056ec3`, `1574f9e`, `880d680`
- [x] Build: `** BUILD SUCCEEDED **`

## Self-Check: PASSED
