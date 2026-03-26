---
status: resolved
trigger: "Three interrelated issues observed on-device after previous fix attempt (commit c8a8ba9): 6-hour overnight gap in background monitoring, radio tech stuck on LTE when device is on 5G, chart UX poor with cramped bars and no scrolling."
created: 2026-03-26T10:00:00Z
updated: 2026-03-26T11:00:00Z
---

## Current Focus

hypothesis: All three root causes identified and fixed
test: Build succeeded, awaiting on-device verification
expecting: Background probes via BGAppRefreshTask work during background-only launches; radio tech updates when changed in settings; chart is usable with time window picker and clear axis labels
next_action: User verifies on device

## Symptoms

expected:
  1. Continuous 60-second probe cycle running 24/7 including when phone is locked/sleeping
  2. Radio access technology should update in real-time when user switches from LTE to 5G
  3. Drop Timeline chart should be usable — scrollable, clear time window, appropriately scaled

actual:
  1. Events logged 22:30-22:37 on 3/25, then NO events until 04:58 on 3/26 (~6 hour gap overnight). Only resumes when user opens app.
  2. App shows "LTE" even though iOS status bar shows "5G". Even stopping/restarting monitoring doesn't update.
  3. Chart shows 3 red bars clustered at left edge around hour 22, rest empty, no scrolling, unclear timeframe.

errors: No crashes. App works fine in foreground.

reproduction:
  1. Open app, see events. Lock phone, sleep. Wake hours later — no events logged during gap.
  2. Switch from LTE to 5G in iOS settings. Open CellGuard — still shows "LTE". Stop/restart — still "LTE".
  3. Look at Drop Timeline chart — bars cramped on left, no scroll, unclear timeframe.

started: Issues present since first install. Previous fix (c8a8ba9) attempted to address background monitoring but gap persists.

## Eliminated

## Evidence

- timestamp: 2026-03-26T10:02:00Z
  checked: ISSUE 1 - BGAppRefreshTask handling path
  found: BGAppRefreshTask handler in AppDelegate posts a NotificationCenter notification ("com.cellguard.handleRefresh"). CellGuardApp observes this via SwiftUI .onReceive() view modifier. During background-only launches (e.g., BGAppRefreshTask firing overnight with no UI scene), .onReceive never fires because no SwiftUI view hierarchy exists. The task is never completed and no probe runs. Additionally, BGAppRefreshTask was only scheduled when entering background (ContentView.onChange scenePhase == .background), which also doesn't fire during background-only launches.
  implication: ROOT CAUSE 1 — BGAppRefreshTask handling is broken for background-only launches. Must move task handler to AppDelegate and schedule refresh on every launch (not just foreground-to-background transitions).

- timestamp: 2026-03-26T10:03:00Z
  checked: ISSUE 2 - CTTelephonyNetworkInfo radio tech caching
  found: ConnectivityMonitor creates a single CTTelephonyNetworkInfo instance at init (line 97). All radio tech reads go through this one instance. CTTelephonyNetworkInfo is known to cache the radio access technology dictionary from creation time. When the user changes cellular settings (LTE <-> 5G), the cached dictionary on the existing instance may not reflect the change. Even the notification callback reads from the same stale instance. Even stopping/restarting monitoring doesn't help because startMonitoring() also reads from the same cached instance.
  implication: ROOT CAUSE 2 — Single CTTelephonyNetworkInfo instance returns stale cached radio tech. Must create fresh instances when reading current radio tech.

- timestamp: 2026-03-26T10:04:00Z
  checked: ISSUE 3 - DropTimelineChart UX
  found: Chart uses a fixed 6-hour minimum domain from earliest event to now. With only 3 drop events at hour 22 and current time being hours later, bars cluster at left with vast empty space. No time window picker, no scrolling, no axis customization, no drop count summary.
  implication: ROOT CAUSE 3 — Chart needs selectable time windows (6h/24h/7d), proper axis labels, and drop count summary.

## Resolution

root_cause: |
  1. BACKGROUND TASK HANDLING BROKEN: BGAppRefreshTask handler used SwiftUI .onReceive() which only
     fires when a view hierarchy exists. Background-only launches (no scene) never handle the task.
     Also, BGAppRefreshTask was only scheduled on foreground-to-background transitions, not on every launch.
  2. RADIO TECH CACHED: Single CTTelephonyNetworkInfo instance caches radio tech from creation time.
     All reads (initial, notification callback, event capture) returned stale values.
  3. CHART UX: Static chart with fixed 6-hour domain, no time window selection, poor axis labels.

fix: |
  1. AppDelegate.swift: Moved BGAppRefreshTask handling from SwiftUI .onReceive to AppDelegate directly.
     Added static sharedMonitor property set by CellGuardApp.init(). Task handler now runs probe via
     sharedMonitor and schedules next refresh — works regardless of UI state. CellGuardApp.init() now
     schedules BGAppRefreshTask on every launch (foreground or background), not just on scene phase change.
  2. ConnectivityMonitor.swift: Changed captureRadioTechnology() and captureCarrierName() to create
     fresh CTTelephonyNetworkInfo instances on each call instead of using the cached property. Updated
     setupRadioTechObserver() notification callback to use fresh instance. Added observer token storage
     and cleanup in stopMonitoring() via removeRadioTechObserver(). Initial read in startMonitoring()
     also uses fresh instance.
  3. DropTimelineChart.swift: Complete rewrite with selectable time windows (6h/24h/7d), proper axis
     marks with time formatting, fixed domain from (now - window) to now, drop count summary, and
     adaptive bucket sizes per window (15min/1h/6h).

verification: Build succeeded. On-device verified — all three issues confirmed fixed. Additional UI polish applied:
  - Fixed BGTask crash (scheduleAppRefresh called before handler registration — moved to AppDelegate)
  - Radio tech explanation added to HealthDetailSheet with human-readable labels
  - HealthDetailSheet made scrollable with .large detent option
  - Dashboard layout optimized for single-screen no-scroll design
  - Chart height, spacing, axis padding, and 7d calendar alignment refined
files_changed:
  - CellGuard/App/AppDelegate.swift
  - CellGuard/CellGuardApp.swift
  - CellGuard/Services/ConnectivityMonitor.swift
  - CellGuard/Views/DashboardView.swift
  - CellGuard/Views/DropTimelineChart.swift
  - CellGuard/Views/HealthDetailSheet.swift
