---
phase: 03-background-lifecycle
plan: 03
subsystem: ui, lifecycle
tags: [swiftui, health-status, app-lifecycle, bgapprefresh, environment-injection]

# Dependency graph
requires:
  - phase: 03-background-lifecycle/plan-01
    provides: LocationService, AppDelegate, gap detection, monitoringGap event type
  - phase: 03-background-lifecycle/plan-02
    provides: MonitoringHealthService, ProvisioningProfileService
provides:
  - Full app lifecycle wiring connecting all Phase 3 services
  - Health status bar in ContentView (colored dot + label + chevron, tappable)
  - HealthDetailSheet with degraded reasons, profile expiry, last wake time, start/stop controls
  - Monitoring gap event rendering with pause.circle icon and time range
  - BGAppRefreshTask handling via NotificationCenter forwarding from AppDelegate
  - Auto-resume monitoring from UserDefaults on launch
  - Real-time health re-evaluation via onConditionChanged closure (BKG-04)
affects: [04-ui-evidence-export]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Environment injection for all services (monitor, locationService, healthService, profileService)"
    - "onConditionChanged closure for decoupled real-time health updates"
    - "NotificationCenter-based BGAppRefreshTask forwarding from AppDelegate to app body"
    - "RelativeDateTimeFormatter for human-readable last-wake timestamps"

key-files:
  created:
    - CellGuard/Views/HealthDetailSheet.swift
  modified:
    - CellGuard/CellGuardApp.swift
    - CellGuard/Views/ContentView.swift

key-decisions:
  - "Environment injection for all four services rather than singleton access"
  - "Half-sheet (.medium detent) for health detail to keep dashboard visible behind"
  - "Conditional probe timer start only when monitoring is active (fix from checkpoint feedback)"

patterns-established:
  - "Service environment pattern: create in CellGuardApp.init, inject via .environment(), consume via @Environment"
  - "Health status bar pattern: colored dot + label + chevron, tappable to open detail sheet"
  - "Gap event row pattern: pause.circle icon with time range display"

requirements-completed: [BKG-01, BKG-03, BKG-04, BKG-05, DAT-03]

# Metrics
duration: 8min
completed: 2026-03-25
---

# Phase 3 Plan 3: App Lifecycle Wiring Summary

**Full lifecycle wiring connecting LocationService, MonitoringHealthService, and ProvisioningProfileService into CellGuardApp with health status bar UI and HealthDetailSheet**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-25T15:55:00Z
- **Completed:** 2026-03-25T16:03:29Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments
- Wired all Phase 3 services into CellGuardApp with environment injection and auto-resume from UserDefaults
- Built tappable health status bar showing monitoring state with colored dot, label, and chevron
- Created HealthDetailSheet with degraded reasons, fix instructions, profile expiry, last wake time, and start/stop controls
- Added monitoring gap event rendering with pause.circle icon and time range
- Connected BGAppRefreshTask handling via NotificationCenter forwarding from AppDelegate
- Wired real-time health re-evaluation via onConditionChanged closure for BKG-04

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire services into CellGuardApp lifecycle and update ContentView + HealthDetailSheet** - `c39cbe8` (feat) + `dc8c264` (fix: improve health bar tap target, conditional probe timer, stable wake time)
2. **Task 2: Verify health status bar and detail sheet** - checkpoint approved by user

## Files Created/Modified
- `CellGuard/CellGuardApp.swift` - Added AppDelegate adaptor, all service creation/injection, auto-resume, BGRefresh handling, health observation
- `CellGuard/Views/ContentView.swift` - Health status bar with tap-to-sheet, gap event rows, scene phase health re-evaluation, BGRefresh scheduling
- `CellGuard/Views/HealthDetailSheet.swift` - New half-sheet with health status, degraded reasons, profile expiry, last wake, start/stop controls

## Decisions Made
- Environment injection for all four services rather than singleton access -- keeps services testable and decoupled
- Half-sheet (.medium detent) for health detail to keep dashboard visible behind
- Conditional probe timer start only when monitoring is active (added during checkpoint fix)
- Used RelativeDateTimeFormatter for last-wake display ("2 minutes ago" style)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Improved health bar tap target and conditional probe timer**
- **Found during:** Task 2 (checkpoint verification feedback)
- **Issue:** Health bar tap target was small; probe timer started unconditionally; last wake time didn't use stable formatting
- **Fix:** Expanded tap target, made probe timer conditional on monitoring state, improved wake time display
- **Files modified:** CellGuard/Views/ContentView.swift, CellGuard/Views/HealthDetailSheet.swift
- **Verification:** User approved after fix
- **Committed in:** dc8c264

---

**Total deviations:** 1 auto-fixed (1 bug fix from checkpoint feedback)
**Impact on plan:** Minor UI polish fix. No scope creep.

## Known Minor Issues (from checkpoint feedback)
- **Last Background Wake doesn't refresh live while sheet is open** -- RelativeDateTimeFormatter text is computed once on sheet appear; would need a timer to update live. Low priority, cosmetic only.
- **Duplicate probes within same minute** -- Probe timer and manual probe can overlap. Not a data integrity issue (duplicate probes are harmless logged events). Can be deduplicated in Phase 4 if needed.

## Issues Encountered
None -- plan executed as written with one minor UI fix from checkpoint feedback.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 (Background Lifecycle) is complete: all services built, wired, and verified
- App has full background monitoring capability with gap detection and health indicators
- Ready for Phase 4 (UI and Evidence Export): dashboard, event detail, export, summary report, charts
- Minor issues noted above are cosmetic and do not block Phase 4

## Self-Check: PASSED

- All 3 source files verified on disk
- Both commits (c39cbe8, dc8c264) verified in git log
- SUMMARY.md created successfully

---
*Phase: 03-background-lifecycle*
*Completed: 2026-03-25*
