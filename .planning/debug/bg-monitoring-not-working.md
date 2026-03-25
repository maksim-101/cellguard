---
status: resolved
trigger: "Background monitoring not functioning — probing and event logging only occurs when app is in foreground. Drop Timeline chart renders incorrectly."
created: 2026-03-25T22:30:00Z
updated: 2026-03-25T22:30:00Z
---

## Current Focus

hypothesis: Multiple root causes identified - see Evidence section
test: code analysis complete, preparing fixes
expecting: N/A - root causes confirmed via code reading
next_action: implement fixes for all three issues

## Symptoms

expected: Continuous 60-second probe cycle running 24/7 in background via significant location changes + CLServiceSession + BGAppRefreshTask. Drop Timeline chart should show discrete bars per time bucket.
actual: Events only logged when app is actively open in foreground. Event timestamps cluster at times when user opened the app (21:43, 21:57, 22:04, 22:09) with no events between sessions. Dashboard shows "Monitoring Degraded" (yellow). Drop Timeline chart shows a massive filled red rectangle covering most of the chart area instead of discrete time-bucketed bars. Two "Silent Failure" events at 21:44 and 21:57 may be false positives at app launch.
errors: No crash — app runs fine in foreground. "Monitoring Degraded" status displayed.
reproduction: Install app, open it (events log), background it (events stop), reopen it (events resume).
started: First install — never worked in background.

## Eliminated

## Evidence

- timestamp: 2026-03-25T22:35:00Z
  checked: CellGuardApp.swift auto-resume logic
  found: Auto-resume is in `.onAppear {}` which only fires when ContentView's body is rendered (i.e., foreground UI display). When iOS relaunches the app for a location event, if no scene is created (background launch), onAppear NEVER fires. The AppDelegate sets UserDefaults "launchedForLocation" but NOTHING reads it to actually start monitoring.
  implication: ROOT CAUSE 1 - Background relaunch from significant location changes never starts monitoring services because the auto-resume code is in a SwiftUI view lifecycle callback that doesn't fire during background launches.

- timestamp: 2026-03-25T22:35:00Z
  checked: ConnectivityMonitor.swift probe timer
  found: startProbeTimer() uses Timer.scheduledTimer() on the main RunLoop. iOS suspends RunLoop timers when app goes to background. The code explicitly stops the timer in ContentView.onChange(of: scenePhase) when entering background, and restarts it when returning to active. The ONLY background probe mechanism is (a) significant location change wake calling runSingleProbe(), and (b) BGAppRefreshTask. Both of these depend on the auto-resume logic firing, which it doesn't (see ROOT CAUSE 1).
  implication: Confirms foreground-only behavior. The probe timer is correctly stopped in background but the wake-then-probe path is broken because monitoring never starts on background relaunch.

- timestamp: 2026-03-25T22:35:00Z
  checked: MonitoringHealthService.swift degraded conditions
  found: Health shows "degraded" when ANY of these are true: Low Power Mode enabled, Background App Refresh disabled in settings, location authorized as "When In Use" only, or location denied/restricted. The user sees "Monitoring Degraded" (orange), which means one of these conditions is true. Most likely: location is "When In Use" (not "Always"), OR Background App Refresh is disabled in system settings.
  implication: The degraded status is probably accurate - if location is only "When In Use", significant location changes won't wake the app from terminated state. This compounds ROOT CAUSE 1.

- timestamp: 2026-03-25T22:36:00Z
  checked: DropTimelineChart.swift chart rendering
  found: The chart uses `BarMark(x: .value("Time", event.timestamp, unit: .hour), y: .value("Drops", 1))`. With `.hour` temporal binning, bars spanning the same hour get stacked. BUT the issue is that bars use the raw timestamp and Swift Charts creates bars with width spanning the full hour. When multiple drop events cluster in the same short time period (all within ~30min window at app open times), the bars overlap and stack into a massive filled rectangle. The real problem: there is no `.stacking(.standard)` or explicit mark width. Swift Charts BarMark with temporal x-axis defaults to spanning the full unit width (.hour). With all events in hours 21 and 22, the bars span those full hours and stack vertically, creating a filled rectangle.
  implication: ROOT CAUSE 2 - DropTimelineChart needs explicit bar width control or should aggregate counts per time bucket rather than creating one BarMark per event with y=1.

- timestamp: 2026-03-25T22:37:00Z
  checked: Silent failure false positives at app launch
  found: When app opens, startProbeTimer() fires runProbe() immediately (line 180). At that moment the phone may still be establishing network after wake. If the probe fires before the network is ready, it fails, and if currentPathStatus==.satisfied and currentInterfaceType==.cellular (from a stale NWPathMonitor state), it classifies as silentFailure. The isInitialUpdate flag only suppresses the first NWPathMonitor callback, not the first probe.
  implication: ROOT CAUSE 3 - The immediate first probe on app launch races with network readiness, producing false silent failure events.

## Resolution

root_cause: |
  Three interrelated issues:
  1. BACKGROUND RELAUNCH DEAD CODE: Auto-resume monitoring is in CellGuardApp's `.onAppear {}` which only fires when the UI renders (foreground). When iOS relaunches the app for a significant location change (background launch), no scene is created, onAppear never fires, and monitoring never starts. AppDelegate sets "launchedForLocation" flag but nothing reads it.
  2. CHART RENDERING: DropTimelineChart creates one BarMark per raw event with y=1 and .hour unit binning. Swift Charts renders each bar spanning the full hour width. Multiple events in the same hour produce stacked full-width bars creating a solid filled rectangle instead of discrete bars.
  3. FALSE POSITIVE SILENT FAILURES: The immediate first probe on startProbeTimer() races with network establishment after app launch, producing false silentFailure classifications when the path status is stale-satisfied but the network isn't actually ready yet.
fix: |
  1. CellGuardApp.swift: Moved auto-resume monitoring from .onAppear (UI-only) to init() so it fires on ALL launches including background relaunches from significant location changes. The onAppear now only handles health observation setup and initial health evaluation.
  2. DropTimelineChart.swift: Replaced per-event BarMark rendering with pre-aggregated hourly TimeBucket approach. Events are grouped by (hour, type) and counted, then each bucket renders a single BarMark with the aggregated count. This prevents overlapping full-width bars from creating a solid filled rectangle.
  3. ConnectivityMonitor.swift: Added 5-second delay before the first probe in startProbeTimer() to let NWPathMonitor deliver its initial callback and the network stabilize after app launch/wake. Prevents false silentFailure classifications from stale path state.
verification: Build succeeded (xcodebuild). Requires on-device verification for background behavior.
files_changed:
  - CellGuard/CellGuardApp.swift
  - CellGuard/Views/DropTimelineChart.swift
  - CellGuard/Services/ConnectivityMonitor.swift
