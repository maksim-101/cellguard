---
phase: 02-core-monitoring
verified: 2026-03-25T14:00:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 2: Core Monitoring — Verification Report

**Phase Goal:** Build the ConnectivityMonitor service — NWPathMonitor integration, active HEAD probe for silent modem failures, CoreTelephony metadata capture, and SwiftUI lifecycle wiring.
**Verified:** 2026-03-25
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Every NWPathMonitor transition produces a logged event with correct event type, pathStatus, and interfaceType | VERIFIED | `processPathChange()` at L344–400 covers all 4 cases: overt drop, restored, Wi-Fi fallback, other. `mapPathStatus()` and `detectPrimaryInterface()` provide correct mapping. |
| 2  | A cellular-to-wifi fallback while path remains satisfied is logged as a distinct pathChange event with interfaceType .wifi | VERIFIED | `ConnectivityMonitor.swift` L375: `previousInterfaceType == .cellular && newInterface == .wifi && newStatus == .satisfied` explicitly checks this case before the generic catch-all. |
| 3  | Drop duration is calculated on connectivityRestored events as seconds since the drop-start event | VERIFIED | `ConnectivityMonitor.swift` L363: `let dropDuration = dropStartDate.map { Date().timeIntervalSince($0) }` followed by `dropDurationSeconds: dropDuration` in `logEvent`. |
| 4  | The initial NWPathMonitor callback does NOT produce a spurious event | VERIFIED | `isInitialUpdate = true` set in `startMonitoring()`, guard at L309–316 silently captures initial state and returns without logging. |
| 5  | Rapid path flapping within 500ms is debounced to a single event | VERIFIED | `debounceTask?.cancel()` + `Task.sleep(for: .milliseconds(500))` at L321–332. Only the final update in a rapid sequence survives. |
| 6  | A HEAD probe fires every 60 seconds in foreground; probe failure while path is satisfied + cellular is classified as silentFailure | VERIFIED | `startProbeTimer()` at L169–177 uses `Timer.scheduledTimer(withTimeInterval: probeInterval)`. `runProbe()` at L196–262 catches errors and checks `capturedStatus == .satisfied && capturedInterface == .cellular` for silentFailure classification. |
| 7  | Each event includes radio access technology (or nil) and carrier name on best-effort basis | VERIFIED | `captureRadioTechnology()` at L285–287 calls `serviceCurrentRadioAccessTechnology?.values.first`. `captureCarrierName()` at L292–294 calls `serviceSubscriberCellularProviders?.values.first?.carrierName`. Both called from `logEvent()`. |
| 8  | ConnectivityMonitor is created once in CellGuardApp and injected via environment; monitoring starts automatically and probe timer pauses in background | VERIFIED | `CellGuardApp.swift` creates `ConnectivityMonitor(eventStore: store)` once in `init()`, injects via `.environment(monitor)`. `ContentView.swift` calls `monitor.startMonitoring()` in `.onAppear`, `stopProbeTimer()` on `.background`, `startProbeTimer()` on `.active`. |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `CellGuard/Services/ConnectivityMonitor.swift` | NWPathMonitor coordinator with probe, telemetry, and location | VERIFIED | 469 lines. Contains `@Observable final class ConnectivityMonitor`, all 4 classification cases, probe subsystem, CoreTelephony integration, location passthrough. |
| `CellGuard/CellGuardApp.swift` | App entry point wiring ConnectivityMonitor with EventStore | VERIFIED | 23 lines. Contains `ConnectivityMonitor(eventStore: store)` and `.environment(monitor)`. |
| `CellGuard/Views/ContentView.swift` | ContentView receiving monitor via environment, showing monitoring status | VERIFIED | 74 lines. Contains `@Environment(ConnectivityMonitor.self) private var monitor`, status bar with `isMonitoring` and `currentRadioTechnology`, `startMonitoring()` call. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CellGuardApp.swift` | `ConnectivityMonitor.swift` | `ConnectivityMonitor(eventStore: store)` | WIRED | L13 of CellGuardApp.swift: `_monitor = State(initialValue: ConnectivityMonitor(eventStore: store))` |
| `ConnectivityMonitor.swift` | `EventStore.swift` | `eventStore.insertEvent()` | WIRED | L466: `try? await eventStore.insertEvent(event)` called from every `logEvent` invocation |
| `ConnectivityMonitor.swift` | `ConnectivityEvent.swift` | `ConnectivityEvent(...)` initializer | WIRED | L449–463: full ConnectivityEvent init with all fields populated |
| `ConnectivityMonitor.swift` | `https://captive.apple.com/hotspot-detect.html` | URLSession HEAD request | WIRED | L73: `probeURL` constant; L201: `request.httpMethod = "HEAD"`; L207: `probeSession.data(for: request)` |
| `ConnectivityMonitor.swift` | CoreTelephony | `serviceCurrentRadioAccessTechnology` | WIRED | L136, L276, L286: three call sites; also `CTServiceRadioAccessTechnologyDidChange` NotificationCenter at L271 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MON-01 | 02-01-PLAN.md | NWPathMonitor path changes logged with correct event type | SATISFIED | `handlePathUpdate` + `processPathChange` in ConnectivityMonitor.swift cover all NWPath.Status transitions |
| MON-02 | 02-02-PLAN.md | Periodic HEAD probe every 60s to detect silent modem failures | SATISFIED | `startProbeTimer()` schedules 60s repeating timer; `runProbe()` performs HEAD request |
| MON-03 | 02-02-PLAN.md | Probe timeout while path satisfied classified as silentFailure | SATISFIED | `runProbe()` catch block at L236: `capturedStatus == .satisfied && capturedInterface == .cellular` -> `.silentFailure` event type |
| MON-04 | 02-02-PLAN.md | Radio access technology captured via CTTelephonyNetworkInfo | SATISFIED | `captureRadioTechnology()` + `setupRadioTechObserver()` using NotificationCenter `.CTServiceRadioAccessTechnologyDidChange`; live updates to `currentRadioTechnology` |
| MON-05 | 02-02-PLAN.md | Carrier metadata captured best-effort (nil acceptable) | SATISFIED | `captureCarrierName()` uses `serviceSubscriberCellularProviders?.values.first?.carrierName`; documented nil fallback in code comment |
| MON-06 | 02-01-PLAN.md | Wi-Fi fallback after cellular drop detected and logged | SATISFIED | Case 3 in `processPathChange()`: `previousInterfaceType == .cellular && newInterface == .wifi && newStatus == .satisfied` |
| DAT-02 | 02-01-PLAN.md | Drop duration stored on restoration event | SATISFIED | `dropStartDate` set on drop; `Date().timeIntervalSince(dropStartDate)` computed on `.connectivityRestored`; passed as `dropDurationSeconds` |
| DAT-04 | 02-02-PLAN.md | Coarse location attached to each event | SATISFIED | `lastLocation` tuple attached in `logEvent()` at L459–461; `updateLocation()` public API available for Phase 3; nil until Phase 3 plugs in CLLocationManager (by design) |

**Orphaned requirements check:** REQUIREMENTS.md traceability table maps MON-01 through MON-06, DAT-02, DAT-04 all to Phase 2. Every Phase 2 requirement is claimed by the two plans. No orphaned requirements found.

---

### Anti-Patterns Found

None detected.

Scanned for: TODO/FIXME/PLACEHOLDER comments, empty implementations, ObservableObject/Combine usage, hardcoded empty data flowing to render, stub return patterns.

Results:
- No TODO/FIXME/PLACEHOLDER comments in any modified file
- No ObservableObject or Combine imports
- No empty handler bodies (all event classifications log real events)
- `probeSession` closure-initialized `let` (not `lazy`) — a documented necessary deviation from plan due to `@Observable` macro incompatibility; functionally equivalent
- `serviceCurrentRadioAccessTechnologyDidUpdateNotifier` replaced with `NotificationCenter` — documented necessary deviation; functionally equivalent

---

### Human Verification Required

The following behaviors require a physical iPhone 17 Pro Max running iOS 26 to verify:

#### 1. Silent Modem Failure Detection on Real Hardware

**Test:** With iOS debugger detached, force a "baseband attached but unreachable" state (e.g., toggle airplane mode off while in an area with weak signal or reproduce the known iPhone 17 Pro Max baseband failure). Observe the event log.
**Expected:** A `silentFailure` event appears within 60 seconds of the modem becoming unreachable while NWPathMonitor still reports `.satisfied + .cellular`.
**Why human:** Cannot simulate the specific baseband failure mode in Simulator. The race-condition safety (captured state before `await`) and the 10s probe timeout only exercise realistically on device.

#### 2. Background Probe Timer Lifecycle

**Test:** Launch app, verify probe timer running (probeSuccess events appear), background the app for 2 minutes, return to foreground.
**Expected:** Timer pauses in background (no events during suspension), resumes on foreground return, first foreground probe fires immediately.
**Why human:** iOS background timer suspension behavior cannot be fully tested in Simulator.

#### 3. CTTelephonyNetworkInfo on iOS 26

**Test:** On iPhone 17 Pro Max with iOS 26, check that `radioTechnology` field in logged events contains a non-nil string (e.g., "CTRadioAccessTechnologyNR" or "CTRadioAccessTechnologyLTE") rather than nil.
**Expected:** `radioTechnology` is non-nil on cellular events. `carrierName` may be nil (acceptable per MON-05).
**Why human:** CTTelephonyNetworkInfo behavior on iOS 26 SDK cannot be confirmed without real device; the API was redirected from block-based notifier to NotificationCenter in this implementation.

---

### Gaps Summary

No gaps. All 8 observable truths are verified by codebase inspection. All 8 requirement IDs (MON-01 through MON-06, DAT-02, DAT-04) are implemented with substantive, wired code. No stubs or placeholder implementations found in any of the 3 modified files.

The only open items are device-level behaviors (items 1–3 above) that require physical hardware and cannot be confirmed statically. These do not block phase completion — they are runtime behaviors that follow directly from the verified implementation.

---

_Verified: 2026-03-25_
_Verifier: Claude (gsd-verifier)_
