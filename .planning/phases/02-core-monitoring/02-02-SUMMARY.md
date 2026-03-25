---
phase: 02-core-monitoring
plan: 02
subsystem: monitoring
tags: [nwpathmonitor, urlsession, coretelephony, head-probe, silent-failure]

# Dependency graph
requires:
  - phase: 02-core-monitoring/01
    provides: "ConnectivityMonitor with NWPathMonitor path classification"
  - phase: 01-foundation
    provides: "ConnectivityEvent model, EventStore persistence"
provides:
  - "HEAD probe subsystem with 60-second active connectivity verification"
  - "Silent modem failure detection (path satisfied + cellular but probe fails)"
  - "CoreTelephony radio technology capture on every event"
  - "Best-effort carrier name capture via deprecated CTCarrier API"
  - "Location passthrough from lastLocation to all events"
  - "Full app lifecycle wiring: CellGuardApp creates and injects ConnectivityMonitor"
  - "Probe timer foreground/background lifecycle management"
affects: [03-background-lifecycle, 04-ui-export]

# Tech tracking
tech-stack:
  added: [CoreTelephony, URLSession-probe]
  patterns: [captured-state-before-async, probe-timer-lifecycle, environment-injection]

key-files:
  created: []
  modified:
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/CellGuardApp.swift
    - CellGuard/Views/ContentView.swift

key-decisions:
  - "Used NotificationCenter .CTServiceRadioAccessTechnologyDidChange instead of block-based notifier (API name mismatch in SDK)"
  - "Used closure-initialized let for probeSession instead of lazy var (incompatible with @Observable macro)"
  - "Hardcoded probe timeout in URLSession config (10s) since lazy properties cannot reference self in @Observable"

patterns-established:
  - "Captured state pattern: snapshot path status/interface before awaiting async probe to avoid race conditions"
  - "Environment injection: @Observable class injected via .environment() in CellGuardApp, received via @Environment(Type.self) in views"
  - "Probe timer lifecycle: start on view appear and foreground return, stop on background entry"

requirements-completed: [MON-02, MON-03, MON-04, MON-05, DAT-04]

# Metrics
duration: 3min
completed: 2026-03-25
---

# Phase 02 Plan 02: Probe + Telemetry Summary

**HEAD probe to captive.apple.com every 60s with silent modem failure detection, CoreTelephony radio/carrier capture, and full app lifecycle wiring**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-25T13:43:46Z
- **Completed:** 2026-03-25T13:46:53Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- HEAD probe fires every 60 seconds to captive.apple.com/hotspot-detect.html, detecting silent modem failures when probe fails while NWPathMonitor reports satisfied + cellular
- Every ConnectivityEvent now includes radio access technology (CTTelephonyNetworkInfo) and best-effort carrier name
- ConnectivityMonitor fully wired into app lifecycle: created once in CellGuardApp with EventStore, injected into ContentView via SwiftUI environment
- ContentView shows live monitoring status indicator and current radio technology (e.g., "NR" for 5G, "LTE")
- Probe timer pauses on background entry and resumes on foreground return

## Task Commits

Each task was committed atomically:

1. **Task 1: Add HEAD probe, silent failure detection, and CoreTelephony** - `c81a58e` (feat)
2. **Task 2: Wire ConnectivityMonitor into CellGuardApp and ContentView** - `282abeb` (feat)

## Files Created/Modified
- `CellGuard/Services/ConnectivityMonitor.swift` - Added HEAD probe (runProbe), silent failure detection, CoreTelephony radio/carrier capture, probe timer management
- `CellGuard/CellGuardApp.swift` - Creates ModelContainer, EventStore, ConnectivityMonitor; injects monitor via .environment()
- `CellGuard/Views/ContentView.swift` - Receives monitor via @Environment, shows status bar, manages probe timer on scene phase changes

## Decisions Made
- Used NotificationCenter `.CTServiceRadioAccessTechnologyDidChange` for radio tech change observation instead of the block-based `serviceCurrentRadioAccessTechnologyDidUpdateNotifier` (API name did not exist in the SDK as documented)
- Used closure-initialized `let` for `probeSession` instead of `lazy var` because @Observable macro is incompatible with lazy stored properties
- Hardcoded probe timeout value (10s) in the URLSession configuration closure since lazy/closure initializers in @Observable classes cannot reference `self` properties

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed @Observable incompatibility with lazy var**
- **Found during:** Task 1 (HEAD probe implementation)
- **Issue:** Plan specified `private lazy var probeSession` but @Observable macro transforms stored properties and is incompatible with `lazy`
- **Fix:** Changed to `private let probeSession` with closure initializer, hardcoded timeout value (10) instead of referencing `self.probeTimeout`
- **Files modified:** CellGuard/Services/ConnectivityMonitor.swift
- **Verification:** xcodebuild BUILD SUCCEEDED
- **Committed in:** c81a58e (Task 1 commit)

**2. [Rule 1 - Bug] Fixed incorrect CTTelephonyNetworkInfo API name**
- **Found during:** Task 1 (CoreTelephony integration)
- **Issue:** Plan specified `serviceCurrentRadioAccessTechnologyDidUpdateNotifier` but this member does not exist on CTTelephonyNetworkInfo in the iOS 26 SDK
- **Fix:** Used NotificationCenter with `.CTServiceRadioAccessTechnologyDidChange` notification instead
- **Files modified:** CellGuard/Services/ConnectivityMonitor.swift
- **Verification:** xcodebuild BUILD SUCCEEDED
- **Committed in:** c81a58e (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes required for compilation. Functionally equivalent to planned behavior. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all data sources are wired (radio tech from CTTelephonyNetworkInfo, carrier from CTCarrier, location from lastLocation passthrough). Location updates will be nil until Phase 3 plugs in CLLocationManager, which is by design.

## Next Phase Readiness
- Core monitoring engine is complete: path changes (Plan 01) + probe/silent failure detection + telemetry (Plan 02)
- Ready for Phase 3 (Background Lifecycle): significant location changes for background wake, CLServiceSession, BGAppRefreshTask
- Probe timer currently foreground-only; Phase 3 adds wake-then-probe pattern
- CTCarrier deprecation warning is expected and documented; carrier name may return nil on iOS 26

---
*Phase: 02-core-monitoring*
*Completed: 2026-03-25*
