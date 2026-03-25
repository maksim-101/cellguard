---
phase: 02-core-monitoring
plan: 01
subsystem: monitoring
tags: [nwpathmonitor, network-framework, connectivity, event-classification, debounce]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: ConnectivityEvent model and EventStore persistence actor
provides:
  - ConnectivityMonitor coordinator with NWPathMonitor integration
  - Path change classification (overt drop, restored, Wi-Fi fallback, other)
  - Drop duration calculation on restoration events
  - 500ms debounce for rapid path flapping
  - Location attachment API for Phase 3 integration
affects: [02-core-monitoring, 03-background-lifecycle, 04-ui-export]

# Tech tracking
tech-stack:
  added: [Network framework (NWPathMonitor)]
  patterns: [path-classification-coordinator, debounce-with-task-sleep, initial-callback-guard]

key-files:
  created:
    - CellGuard/Services/ConnectivityMonitor.swift
  modified: []

key-decisions:
  - "Use availableInterfaces.first instead of usesInterfaceType() to avoid multi-interface ambiguity"
  - "Debounce via Task.sleep(500ms) with cancellation rather than DispatchWorkItem"
  - "Dispatch NWPathMonitor callbacks to MainActor via Task for serialized state access"

patterns-established:
  - "Path classification priority: overt drop > restored > Wi-Fi fallback > other transition"
  - "Initial NWPathMonitor callback suppression via isInitialUpdate flag"
  - "Location injection via updateLocation() method (decoupled from CoreLocation)"

requirements-completed: [MON-01, MON-06, DAT-02]

# Metrics
duration: 2min
completed: 2026-03-25
---

# Phase 02 Plan 01: NWPathMonitor Integration Summary

**ConnectivityMonitor coordinator with 4-case path classification, 500ms debounce, drop duration tracking, and EventStore persistence**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-25T13:40:19Z
- **Completed:** 2026-03-25T13:41:43Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- ConnectivityMonitor class with NWPathMonitor integration classifying every path transition
- Four classification cases: overt drop, connectivity restored (with duration), Wi-Fi fallback (MON-06), other transitions
- Drop duration calculation on restoration events (DAT-02) using dropStartDate tracking
- Initial callback guard prevents spurious startup event
- 500ms debounce prevents duplicate events from rapid path flapping
- Location attachment API ready for Phase 3 CLLocationManager integration

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ConnectivityMonitor with NWPathMonitor integration and path classification** - `b26ab8b` (feat)

**Plan metadata:** [pending final commit]

## Files Created/Modified
- `CellGuard/Services/ConnectivityMonitor.swift` - Core detection engine: NWPathMonitor coordinator with path classification, state tracking, debounce, drop duration calculation, and event persistence via EventStore

## Decisions Made
- Used `availableInterfaces.first` (ordered by system preference) instead of `usesInterfaceType()` to avoid ambiguity when multiple interfaces are active simultaneously
- Debounce implemented via `Task.sleep(for: .milliseconds(500))` with task cancellation, fitting naturally into Swift Concurrency model
- NWPathMonitor callbacks dispatched to MainActor via `Task { @MainActor in }` for serialized state access without explicit locks
- Classification uses if/else chain with priority ordering rather than switch statement, since cases overlap on multiple state dimensions

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ConnectivityMonitor is ready for Plan 02 to add CTTelephonyNetworkInfo (radio tech) and URLSession probe timer
- Phase 3 can call `updateLocation()` to attach location data to events
- Phase 4 UI can observe `currentPathStatus`, `currentInterfaceType`, `isMonitoring` via @Observable

---
*Phase: 02-core-monitoring*
*Completed: 2026-03-25*

## Self-Check: PASSED
