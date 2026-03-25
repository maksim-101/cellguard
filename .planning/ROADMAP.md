# Roadmap: CellGuard

## Overview

CellGuard is built in four phases that follow the evidence pipeline from the inside out. Phase 1 establishes the stable data schema that everything else writes to. Phase 2 builds the detection engine — NWPathMonitor path changes plus active HEAD probes for silent modem failures. Phase 3 solves the hardest problem: making that engine run reliably in the background for 24+ hours without iOS killing it. Phase 4 surfaces the evidence through a minimal UI and produces the export artifacts Apple engineering needs.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - SwiftData schema, EventStore persistence layer, and app shell
- [ ] **Phase 2: Core Monitoring** - NWPathMonitor, HEAD probe, silent failure detection, telemetry, coordinator
- [ ] **Phase 3: Background Lifecycle** - Reliable 24h+ background execution, gap tracking, health indicators
- [ ] **Phase 4: UI and Evidence Export** - Dashboard, event log, export, summary report, Swift Charts visualization

## Phase Details

### Phase 1: Foundation
**Goal**: The ConnectivityEvent data model and persistence layer exist, are stable, and can be written to and queried from background contexts
**Depends on**: Nothing (first phase)
**Requirements**: DAT-01, DAT-06
**Success Criteria** (what must be TRUE):
  1. A ConnectivityEvent record with all required metadata fields (timestamp, event type, path status, interface type, radio tech, carrier, probe result, location, drop duration) can be created and persisted to disk
  2. Persisted events survive app kills and device reboots
  3. The EventStore ModelActor accepts writes from a background context without deadlocking or data corruption
  4. The app launches to a working shell with ModelContainer configured and no crashes
**Plans:** 1 plan

Plans:
- [x] 01-01-PLAN.md — Xcode project, ConnectivityEvent SwiftData model, EventStore @ModelActor, app shell

### Phase 2: Core Monitoring
**Goal**: The app detects every overt cellular drop and every silent modem failure (path satisfied but no data transits), captures full metadata per event, and writes complete ConnectivityEvent records
**Depends on**: Phase 1
**Requirements**: MON-01, MON-02, MON-03, MON-04, MON-05, MON-06, DAT-02, DAT-04
**Success Criteria** (what must be TRUE):
  1. Every NWPathMonitor transition (satisfied/unsatisfied/requiresConnection, interface change) produces a logged event with correct event type classification
  2. A HEAD request probe fires every 60 seconds when the app is in the foreground; a path-satisfied + probe-failure condition is classified and stored as a silentFailure event type
  3. Each event record includes radio access technology from CTTelephonyNetworkInfo (or "Unknown" if unavailable) and carrier name on a best-effort basis
  4. A Wi-Fi fallback after a cellular drop is detected and logged as a distinct interface transition event
  5. Drop duration (time from drop-start to next restoration event) is calculated and stored on the restoration event
**Plans:** 2 plans

Plans:
- [x] 02-01-PLAN.md — ConnectivityMonitor coordinator with NWPathMonitor, path classification, drop duration
- [x] 02-02-PLAN.md — HEAD probe, silent failure detection, CoreTelephony telemetry, app wiring

### Phase 3: Background Lifecycle
**Goal**: The monitoring engine runs reliably for 24+ hours in the background, survives iOS termination and device reboots, and surfaces degraded monitoring conditions to the user
**Depends on**: Phase 2
**Requirements**: BKG-01, BKG-02, BKG-03, BKG-04, BKG-05, DAT-03, DAT-05
**Success Criteria** (what must be TRUE):
  1. After the app is killed by iOS or the device is rebooted, monitoring resumes automatically on next significant location change without any user action
  2. The app runs HEAD probes and logs events in the background for at least 24 hours without the process being terminated by iOS watchdog
  3. The app detects and logs monitoring gaps — periods when iOS suspended the app and no events could be captured — so exported data accurately represents coverage
  4. The user sees a clear monitoring health indicator (active / degraded / paused) whenever Background App Refresh is disabled, Low Power Mode is active, or location authorization is reduced
  5. The provisioning profile expiration date is visible in the UI and the user receives a local notification 48 hours before expiry
**Plans:** 3 plans

Plans:
- [x] 03-01-PLAN.md — LocationService (CLLocationManager + CLServiceSession), AppDelegate, gap detection, monitoringGap event type
- [x] 03-02-PLAN.md — MonitoringHealthService (health aggregation), ProvisioningProfileService (expiry + notification)
- [x] 03-03-PLAN.md — App lifecycle wiring, health status bar UI, HealthDetailSheet, gap event rendering

### Phase 4: UI and Evidence Export
**Goal**: The collected evidence is browsable in a clear minimal UI and exportable as structured files and a human-readable summary suitable for an Apple Feedback Assistant report
**Depends on**: Phase 3
**Requirements**: MON-07, UI-01, UI-02, UI-03, UI-04, EXP-01, EXP-02, EXP-03
**Success Criteria** (what must be TRUE):
  1. The app launches directly to a dashboard showing: monitoring status (active/paused/degraded), current connectivity state, drop counts (24h / 7d / total), and last drop timestamp — with no onboarding beyond required permission prompts
  2. The user can browse all captured events in a scrollable reverse-chronological list and tap any event to see its full metadata
  3. The user can export the complete event log as a structured JSON file via the iOS Share Sheet
  4. The app generates and displays a summary report showing total drops, drop breakdown by type (overt vs silent), average and max duration, drops per day, location distribution, and radio technology distribution
  5. A Swift Charts timeline visualization shows drops over time with silent failures visually distinct from overt drops
  6. A local notification fires after a drop is detected prompting the user to capture a sysdiagnose immediately
**Plans:** 3 plans

Plans:
- [x] 04-01-PLAN.md — Dashboard, event list, event detail views, drop classification helper
- [x] 04-02-PLAN.md — Drop notification (MON-07), JSON export Transferable model (EXP-01)
- [x] 04-03-PLAN.md — Summary report, Swift Charts timeline, dashboard wiring

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 0/1 | Planning complete | - |
| 2. Core Monitoring | 0/2 | Planning complete | - |
| 3. Background Lifecycle | 0/3 | Planning complete | - |
| 4. UI and Evidence Export | 0/3 | Planning complete | - |
