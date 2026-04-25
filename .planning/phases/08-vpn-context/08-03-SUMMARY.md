---
phase: 08-vpn-context
plan: 03
type: execute
status: complete
created: 2026-04-25
updated: 2026-04-25
---

# Plan 08-03 Summary — VPN detection wired into `ConnectivityMonitor`

## What was built

VPN detection, live `@Observable` binding, race-safe capture in `runProbe`,
broad VPN-04 silent-failure reclassification, and the dashboard label hook
for Plan 04 — all in one file.

The Wave 0 device verification (deferred per `08-VERIFICATION-WAVE-0.md`)
is folded in as a one-shot `os.Logger` self-check inside
`captureVPNDetectorBool()` that dumps the full `__SCOPED__` key list and
the matched prefix on the first invocation per app launch.

## Edits A–L (all in `CellGuard/Services/ConnectivityMonitor.swift`)

| ID | Region | Change |
|---|---|---|
| **A** | Imports (lines 1-8) | `import SystemConfiguration` and `import os` already present from prior chunk. |
| **B** | `@Observable` published state (after `currentRadioTechnology` ~line 47) | `private(set) var currentVPNState: VPNState = .disconnected`. |
| **C** | Private state (after `previousPathStatus` ~line 73) | `previousVPNDetectorState: Bool = false`, `vpnReassertingUntil: Date?`, `didEmitVPNSelfCheck: Bool = false`, `vpnLogger = Logger(subsystem: "com.cellguard.connectivity", category: "vpn")`. |
| **D** | After `captureWifiSSID()` | `private func captureVPNDetectorBool() -> Bool` — scans `__SCOPED__` for prefixes `["utun", "ipsec", "tap", "tun", "ppp"]`. Embedded one-shot `os_log` self-check on first call per app launch (sorted key list + matched key + matched prefix, or "NO MATCH"). All log fields marked `privacy: .public` so Console.app shows literal values. |
| **E** | Immediately after D | `private func captureVPNState() -> VPNState` — 6-state machine using `(prev, now)` boolean pair and 5-second `vpnReassertingUntil` window. Mutates `previousVPNDetectorState` exactly once per call. |
| **F** | `handlePathUpdate` | After `currentInterfaceType = newInterface` in both initial-update and steady branches: refreshes `currentVPNState = captureVPNState()`. In the steady branch, also seeds `vpnReassertingUntil = now+5s` whenever the detector is true and `newStatus == .unsatisfied` (so a subsequent `.satisfied` tick within 5s classifies as `.reasserting`). |
| **G + H** | `logEvent` | Signature gains `vpnState: VPNState? = nil` as the LAST parameter. Body computes `let resolvedVPNState = vpnState ?? captureVPNState()` SYNCHRONOUSLY outside the `Task` (D-09). Threaded into `ConnectivityEvent.init(...)` immediately after `wifiSSID:`. |
| **I** | `runProbe` snapshot | `let capturedVPNState = currentVPNState` and `let capturedPathUsesCellular = pathMonitor.currentPath.usesInterfaceType(.cellular)` added immediately after the existing `capturedInterface` line — both snapshotted before `await` (race-safe, parallel to existing pattern). |
| **J** | `runProbe` catch branch | Replaced narrow `capturedInterface == .cellular` with the BROAD trigger (see formula below). Threaded `vpnState: capturedVPNState` into BOTH branches (silentFailure AND probeFailure). Also threaded into the `try` branches (probeSuccess AND HTTP-non-200 probeFailure) so every event records the snapshotted state — total 4 threading sites in `runProbe`. |
| **K** | `effectiveInterfaceLabel` | `var effectiveInterfaceLabel: String` placed alongside the published state (immediately after `currentVPNState`). Returns `"VPN"` when `currentVPNState == .connected || currentVPNState == .reasserting`, else `currentInterfaceType.displayName`. UI-SPEC excludes `.connecting` and `.disconnecting` — they fall through to `displayName` per spec. |
| **L** | `Network.NWPath` qualification | All existing `Network.NWPath` qualifications preserved at lines 361, 465, 479. New code uses `pathMonitor.currentPath.usesInterfaceType(.cellular)` inside method bodies (no qualification needed). No new function signatures take `NWPath`. |

## BROAD trigger as it appears in the catch branch

```swift
let vpnIsUp = capturedVPNState == .connected
    || capturedVPNState == .reasserting
    || capturedVPNState == .connecting
    || capturedVPNState == .disconnecting
let effectivelyCellular = (capturedInterface == .cellular)
    || (vpnIsUp && capturedPathUsesCellular)

if capturedStatus == .satisfied && effectivelyCellular {
    logEvent(type: .silentFailure, ..., vpnState: capturedVPNState)
} else {
    logEvent(type: .probeFailure, ..., vpnState: capturedVPNState)
}
```

This is the user override of CONTEXT.md D-06. The narrow handover scenario
(`vpnState ∈ {.connecting, .reasserting}`) is a strict subset of this BROAD
rule, so it remains covered.

## Embedded Wave 0 self-check telemetry

First call to `captureVPNDetectorBool()` per app launch emits one of:

```
VPN self-check: keys=[<sorted full key list>] matched=<key> prefix=<utun|ipsec|tap|tun|ppp>
VPN self-check: keys=[<sorted full key list>] matched=NO MATCH
VPN self-check: __SCOPED__ unavailable (no proxy settings)
```

Filter Console.app on `subsystem:com.cellguard.connectivity category:vpn` to
read the dump after enabling ProtonVPN on iPhone 17 Pro Max / iOS 26.4.2.

If the dump shows a key that is NOT matched (e.g. an unexpected interface
prefix the live OS uses for the active tunnel), Phase 8.1 polish is a
one-line constant update to the `prefixes` array in `captureVPNDetectorBool()`.
If iCloud Private Relay surfaces a false-positive key, the same polish adds
the documented exclusion filter in the same loop.

## Anti-pattern grep checks (all 0 = clean)

```
NEVPNManager.shared():  0
getifaddrs:             0
NEVPNStatusDidChange:   0
loadFromPreferences:    0
```

(One textual mention of `NEVPNManager` remains in a comment that explains
why we deliberately do NOT use that API. The literal `.shared()` invocation
the acceptance regex targets is absent.)

## Wave 0 Private Relay workaround

NOT integrated yet — verification is deferred to Plan 03's embedded
self-check telemetry, which the user reads from Console.app after first
launch. No false positive observed in advance, so the prefix list is
shipped as-specified. If the self-check dump on the test device shows a
Private Relay key with a matching prefix, Phase 8.1 polish adds the
documented exclusion filter in the same `captureVPNDetectorBool()` loop.

## Hand-off to Plan 04 (UI)

Plan 04 consumes:
- `monitor.effectiveInterfaceLabel: String` (read-only) — drives the
  `DashboardView.connectivityStateCard` interface label, flipping to
  "VPN" only when the tunnel is `.connected` or `.reasserting`.
- `monitor.currentVPNState: VPNState` (read-only) — for any dashboard
  detail rendering that wants the underlying state.
- `event.vpnState: VPNState?` (already provided by Plan 02) — for the
  `EventDetailView` VPN row.

## Build

`xcrun xcodebuild -scheme CellGuard -destination 'generic/platform=iOS' -configuration Debug build` → `** BUILD SUCCEEDED **`.

## Self-Check: PASSED
