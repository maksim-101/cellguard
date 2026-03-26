---
phase: 05-privacy-aware-export
plan: 01
subsystem: export
tags: [privacy, json, codable, appstorage, swiftui]

# Dependency graph
requires:
  - phase: 04-ui-evidence-export
    provides: EventLogExport Transferable wrapper and ShareLink in DashboardView
provides:
  - CodingUserInfoKey.omitLocation extension for conditional JSON encoding
  - Privacy toggle in DashboardView bound to @AppStorage
  - EventLogExport omitLocation parameter pass-through
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [CodingUserInfoKey for encoder-level field filtering, @AppStorage for persistent UI preferences]

key-files:
  created: []
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Models/EventLogExport.swift
    - CellGuard/Views/DashboardView.swift

key-decisions:
  - "CodingUserInfoKey approach for encoder-level location omission rather than separate Codable struct"
  - "Default omitLocation=false preserves existing export behavior (EXPT-03)"

patterns-established:
  - "CodingUserInfoKey pattern: use encoder.userInfo for conditional field encoding"

requirements-completed: [EXPT-01, EXPT-02, EXPT-03]

# Metrics
duration: 1min
completed: 2026-03-26
---

# Phase 05 Plan 01: Privacy-Aware Export Summary

**Privacy toggle strips latitude/longitude/locationAccuracy from JSON export via CodingUserInfoKey encoder flag with @AppStorage persistence**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-26T17:05:49Z
- **Completed:** 2026-03-26T17:07:05Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- ConnectivityEvent conditionally omits location fields based on encoder userInfo flag
- EventLogExport accepts and passes through omitLocation parameter to encoder
- Dashboard privacy toggle bound to @AppStorage persists user preference across app launches

## Task Commits

Each task was committed atomically:

1. **Task 1: Add conditional location encoding to ConnectivityEvent and EventLogExport** - `acb9a87` (feat)
2. **Task 2: Add privacy toggle to DashboardView wired to export** - `b6e8fd6` (feat)

## Files Created/Modified
- `CellGuard/Models/ConnectivityEvent.swift` - Added CodingUserInfoKey.omitLocation extension and conditional location encoding in encode(to:)
- `CellGuard/Models/EventLogExport.swift` - Added omitLocation stored property and encoder.userInfo pass-through
- `CellGuard/Views/DashboardView.swift` - Added @AppStorage toggle and wired omitLocation to EventLogExport

## Decisions Made
- Used CodingUserInfoKey approach for encoder-level location omission -- avoids creating a separate stripped Codable struct, keeps single encode(to:) path
- Default omitLocation=false preserves existing export behavior per EXPT-03 requirement

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Xcode CLI (xcodebuild) not available in this environment -- verified correctness through code inspection and grep checks instead of full build

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Privacy export feature complete -- this is the only plan in Phase 05
- Ready for milestone v1.1 completion

## Self-Check: PASSED
