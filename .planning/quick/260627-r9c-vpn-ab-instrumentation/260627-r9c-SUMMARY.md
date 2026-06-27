---
quick_id: 260627-r9c
title: VPN A/B instrumentation + probe hardening
status: complete
date_completed: 2026-06-27
build_result: BUILD SUCCEEDED (iOS Simulator, iPhone 17 Pro)
branch: feature/apple-support-script
---

# Quick Task 260627-r9c: VPN A/B instrumentation + probe hardening — Summary

Five changes to make CellGuard data trustworthy for a VPN A/B experiment and to harden probe methodology. All tasks committed atomically; build succeeded on first attempt — no exhaustive-switch compiler errors (EventType switches in ConnectivityEvent.swift were the only non-default exhaustive sites; DropClassification.swift uses default: so was unaffected).

## Task 1 — Primary probe HEAD→GET with body validation

**Commit:** d3b79b3  
**Files changed:** `CellGuard/Services/ConnectivityMonitor.swift`

- Changed `httpMethod` from "HEAD" to "GET" so response body is available.
- Changed `let (_, response)` to `let (data, response)` to capture body bytes.
- Added body validation: treat HTTP 200 as `.probeSuccess` only if the UTF-8 decoded body contains "Success" (Apple's canonical captive portal payload). A 200 with a different body is classified as `.probeFailure` with `probeFailureReason: "unexpected body (captive portal?)"`.
- `confirmSilentFailure()` (two-host Cloudflare path) and `makeProbeSession()` (ephemeral session per probe) left unchanged.
- Updated method docstrings throughout.

## Task 2 — Capture CTCellularData.restrictedState

**Commit:** 2f387ca  
**Files changed:** `CellGuard/Services/ConnectivityMonitor.swift`, `CellGuard/Models/ConnectivityEvent.swift`, `CellGuard/Views/EventDetailView.swift`

- Added `private let cellularData = CTCellularData()` (retained instance) and `private var cellularDataRestrictedState: CTCellularDataRestrictedState = .restrictedStateUnknown`.
- In `startMonitoring()`, installed `cellularDataRestrictionDidUpdateNotifier` closure that updates `cellularDataRestrictedState` on the main actor.
- Added `captureCellularDataRestriction() -> String` returning "restricted" / "notRestricted" / "unknown"; called synchronously in `logEvent` alongside `radioTech` and `carrier`.
- Added `ConnectivityEvent.cellularDataRestricted: String?`, wired into init, CodingKeys, `encodeIfPresent` (NOT export-gated), `decodeIfPresent`.
- EventDetailView Cellular section shows "Cellular Data Access" row when field is non-nil.

## Task 3 — Persist matched VPN interface key per event

**Commit:** fd502d0  
**Files changed:** `CellGuard/Services/ConnectivityMonitor.swift`, `CellGuard/Models/ConnectivityEvent.swift`, `CellGuard/Views/EventDetailView.swift`

- Extracted `detectVPNInterface() -> (sortedKeys: [String], matchedKey: String?, matchedPrefix: String?)` as the shared VPN detection core; reads `CFNetworkCopySystemProxySettings.__SCOPED__` once.
- Refactored `captureVPNDetectorBool()` to call `detectVPNInterface()` and retain the one-shot os_log self-check logic.
- Added `private(set) var currentVPNInterface: String?`; set alongside `currentVPNState` in `handlePathUpdate` (live refresh) and the `isInitialUpdate` block.
- Added `vpnInterface: String? = nil` parameter to `logEvent`; resolved via `vpnInterface ?? currentVPNInterface` inside logEvent.
- All six `logEvent` calls in `runProbe` pass `capturedVPNInterface` (pre-await snapshot, matching `capturedVPNState` pattern).
- Added `ConnectivityEvent.vpnInterface: String?`, wired into init, CodingKeys, `decodeIfPresent`, and encoded inside `if !omitLocation` block (same export gate as `vpnState`).
- EventDetailView VPN section shows "Interface" row (e.g., "utun3") when present.

## Task 4 — Dedicated VPN state-transition event

**Commit:** a26fb93  
**Files changed:** `CellGuard/Models/ConnectivityEvent.swift`, `CellGuard/Services/ConnectivityMonitor.swift`, `CellGuard/Views/EventListView.swift`

- Added `EventType.vpnStateChange = 6` with explicit rawValue (migration safety).
- Added `encodingString` case ("vpnStateChange"), `fromEncodingString` case, `displayName` ("VPN State Change") — these are the only exhaustive switches on EventType; all three updated.
- Added `private var previousVPNBoundarySide: Bool = false` to ConnectivityMonitor.
- In `handlePathUpdate`, after `currentVPNState` and `currentVPNInterface` are set, compute `vpnIsPresent = currentVPNState != .disconnected && currentVPNState != .invalid`. When `vpnIsPresent != previousVPNBoundarySide`, update boundary side and log a `.vpnStateChange` event carrying current vpnState + vpnInterface. Only absent↔present crossings emit an event — micro-transitions within the same side (connecting→connected) are suppressed.
- `scheduleDropNotification` already ignores `.vpnStateChange` via its guard (`silentFailure` or `pathChange-to-unsatisfied` only); no change needed.
- Added `case .vpn = "VPN"` to `EventListView.EventFilter` and the corresponding `filteredEvents` branch. The switch over `EventFilter` was the only other exhaustive site; updated.
- `DropClassification.swift` uses `default: return false` — `vpnStateChange` correctly hits the default; no change needed.
- `SummaryReport.swift`, `AnalyticsView.swift`, `DropTimelineChart.swift` use `isDropEvent()` or non-exhaustive logic — no changes needed.

## Task 5 — In-app VPN detection self-check button

**Commit:** 771b8fc  
**Files changed:** `CellGuard/Services/ConnectivityMonitor.swift`, `CellGuard/Views/HealthDetailSheet.swift`

- Added `func vpnDetectionSelfCheck() -> String` on ConnectivityMonitor (public) reusing `detectVPNInterface()`. Returns "matched=\(key) (prefix \(prefix))" / "NO MATCH — keys=[...]" / "no proxy settings".
- The once-per-launch os_log self-check in `captureVPNDetectorBool()` is preserved and independent.
- Added `@State private var vpnSelfCheckResult: String?` and `@State private var showVPNSelfCheck: Bool = false` to HealthDetailSheet.
- Added "Run VPN Detection Self-Check" `.bordered` Button that calls `monitor.vpnDetectionSelfCheck()` and presents result in a `.alert`.

## Build Result

**BUILD SUCCEEDED** — iOS Simulator, iPhone 17 Pro (id: 67444852-5997-45F7-AB70-B51C0D462782), Debug configuration, Xcode 26 / iOS 26.5 SDK. No compiler errors or warnings from the changes.

## Commits

| Task | SHA     | Message |
|------|---------|---------|
| 1    | d3b79b3 | feat: switch primary probe from HEAD to GET with body validation |
| 2    | 2f387ca | feat: capture CTCellularData.restrictedState per event |
| 3    | fd502d0 | feat: persist matched VPN interface key per event |
| 4    | a26fb93 | feat: add EventType.vpnStateChange and tunnel boundary detection |
| 5    | 771b8fc | feat: add in-app VPN detection self-check button in HealthDetailSheet |
