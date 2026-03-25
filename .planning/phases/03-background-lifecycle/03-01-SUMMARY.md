---
phase: 03-background-lifecycle
plan: 01
subsystem: background
tags: [corelocation, cllocationmanager, clservicesession, significant-location-changes, bgtaskscheduler, background-modes]

# Dependency graph
requires:
  - phase: 02-core-monitoring
    provides: ConnectivityMonitor with updateLocation() and probe infrastructure
  - phase: 01-foundation
    provides: ConnectivityEvent model with EventType enum, EventStore for persistence
provides:
  - LocationService with CLLocationManager + CLServiceSession for background execution
  - AppDelegate with location-based relaunch detection and BGTaskScheduler registration
  - monitoringGap event type for gap detection
  - runSingleProbe() public API for background wake-then-probe pattern
  - Info.plist background modes (location, fetch) and location usage descriptions
affects: [03-02 monitoring-health, 03-03 app-integration, 04-dashboard-ui]

# Tech tracking
tech-stack:
  added: [CoreLocation, BackgroundTasks]
  patterns: [wake-then-probe, UserDefaults gap detection, CLServiceSession retention]

key-files:
  created:
    - CellGuard/Services/LocationService.swift
    - CellGuard/App/AppDelegate.swift
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Info.plist

key-decisions:
  - "UserDefaults for gap detection timestamps (fast read on wake, no SwiftData boot delay)"
  - "10-minute gap threshold (600s) to distinguish normal iOS scheduling from actual monitoring gaps"
  - "NotificationCenter-based BGAppRefreshTask forwarding (AppDelegate does not own service references)"

patterns-established:
  - "Wake-then-probe: LocationService receives location -> updates monitor -> detects gaps -> runs probe"
  - "CLServiceSession retention: held for entire monitoring lifetime for iOS 18+ background delivery"
  - "UserDefaults state persistence: monitoringEnabled + lastActiveTimestamp survive app termination"

requirements-completed: [BKG-01, BKG-02, BKG-05, DAT-03, DAT-05]

# Metrics
duration: 4min
completed: 2026-03-25
---

# Phase 03 Plan 01: Background Lifecycle Infrastructure Summary

**LocationService with CLLocationManager + CLServiceSession for persistent background execution, gap detection via UserDefaults timestamps, and AppDelegate for location-based relaunch handling**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-25T15:20:35Z
- **Completed:** 2026-03-25T15:25:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- LocationService owns CLLocationManager and CLServiceSession lifecycle for 24+ hour background monitoring
- Gap detection logs monitoringGap events when app was suspended >10 minutes (distinguishes "no drops" from "app was dead")
- AppDelegate detects location-based relaunches and registers BGTaskScheduler for supplementary wake
- Info.plist declares all required background modes and location permission strings

## Task Commits

Each task was committed atomically:

1. **Task 1: Add monitoringGap event type and make runSingleProbe public** - `478e483` (feat)
2. **Task 2: Create LocationService, AppDelegate, and update Info.plist** - `b194390` (feat)

## Files Created/Modified
- `CellGuard/Services/LocationService.swift` - CLLocationManager + CLServiceSession owner, gap detection, wake-then-probe
- `CellGuard/App/AppDelegate.swift` - Location-based relaunch detection, BGTaskScheduler registration
- `CellGuard/Models/ConnectivityEvent.swift` - Added monitoringGap case (rawValue 5) with display name
- `CellGuard/Services/ConnectivityMonitor.swift` - Added public runSingleProbe() wrapper for background callers
- `CellGuard/Info.plist` - UIBackgroundModes (location, fetch), location usage descriptions, BGTaskSchedulerPermittedIdentifiers

## Decisions Made
- Used UserDefaults (not SwiftData) for gap detection timestamps -- fast read at launch with no SwiftData boot delay
- Set 10-minute (600s) gap threshold to distinguish normal iOS scheduling from actual monitoring gaps
- BGAppRefreshTask handler posts NotificationCenter notification because AppDelegate does not own service references
- Gap events use timestamp of gap START (not current time) so timeline shows when monitoring was lost

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- iOS 26 deprecates `UIApplication.LaunchOptionsKey.location` in favor of CLLocationUpdate/CLMonitor -- logged as a compile warning but the pattern still functions and is the documented approach for significant location change relaunches. Future plan may need to migrate when Apple provides a SwiftUI-native alternative.
- xcode-select pointed to CommandLineTools instead of Xcode.app -- used direct path to xcodebuild as workaround.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all data paths are wired to real services.

## Next Phase Readiness
- LocationService ready for integration into CellGuardApp (03-03 will add @UIApplicationDelegateAdaptor and wire services)
- MonitoringHealthService (03-02) can build on LocationService's authorizationStatus
- All background infrastructure in place for 24+ hour monitoring once wired

## Self-Check: PASSED

- FOUND: CellGuard/Services/LocationService.swift
- FOUND: CellGuard/App/AppDelegate.swift
- FOUND: commit 478e483 (Task 1)
- FOUND: commit b194390 (Task 2)

---
*Phase: 03-background-lifecycle*
*Completed: 2026-03-25*
