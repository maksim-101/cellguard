---
phase: 08-vpn-context
plan: 04
type: execute
status: complete
created: 2026-04-25
updated: 2026-04-25
---

# Plan 08-04 Summary — VPN UI surfaces (EventDetailView + DashboardView)

## What was built

Wired the VPN data produced by Plans 02 (schema) and 03 (service) to the
two user-visible surfaces called out by UI-SPEC: a conditional VPN section
on the event detail screen, and the dashboard's interface label flip plus
privacy toggle copy update.

## Edits 1–4

| ID | File | Region | Change |
|---|---|---|---|
| **1** | `CellGuard/Views/EventDetailView.swift` | After `Section("Wi-Fi")` block (lines 30-34), before `Section("Probe")` (line 36) | New conditional `Section("VPN")` with `LabeledContent("State", value: state.displayName)`. Visibility guard: `if let state = event.vpnState, state != .disconnected, state != .invalid` (3-line conditional binding — equivalent to UI-SPEC §Nil/Empty State Contract). |
| **2** | `CellGuard/Views/EventDetailView.swift` | After existing `extension InterfaceType { var displayName }` (lines 110-122) | New `extension VPNState { var displayName: String }` — six cases mapping to UI-SPEC strings, with `.reasserting → "Reconnecting"` (the deliberate divergence from a literal title-case of the enum case name). |
| **3** | `CellGuard/Views/DashboardView.swift` | `connectivityStateCard` interface row (line 180) | `Text(monitor.currentInterfaceType.displayName)` → `Text(monitor.effectiveInterfaceLabel)`. `.font(.headline)` and all other styling preserved verbatim. |
| **4** | `CellGuard/Views/DashboardView.swift` | Privacy toggle (line 97) | `Toggle("Omit location and Wi-Fi data", isOn: $omitLocation)` → `Toggle("Omit location, Wi-Fi, and VPN data", isOn: $omitLocation)`. Oxford-comma form per UI-SPEC §Privacy Toggle Label Update. `@AppStorage("omitLocationData")` key untouched (renaming would break privacy persistence). |

## Literal copy strings used

| Surface | String |
|---|---|
| Event Detail section header | `"VPN"` |
| Event Detail field label | `"State"` |
| `VPNState.displayName(.invalid)` | `"Invalid"` |
| `VPNState.displayName(.disconnected)` | `"Disconnected"` |
| `VPNState.displayName(.connecting)` | `"Connecting"` |
| `VPNState.displayName(.connected)` | `"Connected"` |
| `VPNState.displayName(.reasserting)` | `"Reconnecting"` |
| `VPNState.displayName(.disconnecting)` | `"Disconnecting"` |
| Dashboard label flip value | `"VPN"` (sourced from `effectiveInterfaceLabel` in `ConnectivityMonitor`) |
| Privacy toggle | `"Omit location, Wi-Fi, and VPN data"` |

The literal word `Reasserting` does not appear anywhere user-facing — `grep -c "Reasserting" EventDetailView.swift` returns 0.

## Surfaces explicitly NOT changed (UI-SPEC lock)

- `EventDetailView.Section("Network")` row `Interface` — KEEPS raw
  `event.interfaceType.displayName`. The dashboard-only override does
  NOT propagate into detail view (UI-SPEC §"Where the override applies
  vs. does not": detail view shows ground truth).
- `EventListView.swift` — untouched.
- `EventLogExport.swift` — untouched. Privacy gating already lives in
  `ConnectivityEvent.encode` (Plan 02).
- `InterfaceType` enum — no `.vpn` case (D-04 anti-pattern guard).
- `@AppStorage("omitLocationData")` key — name unchanged.

## Build

`xcrun xcodebuild -scheme CellGuard -destination 'generic/platform=iOS' -configuration Debug build` → `** BUILD SUCCEEDED **`.

## Acceptance grep summary

```
EventDetailView:
  Section("VPN"):                    1
  visibility guard (3-line):         present (verified via grep -A3)
  LabeledContent("State"):           1
  extension VPNState:                1
  case .reasserting -> "Reconnecting": 1
  case .connected   -> "Connected":  1
  case .connecting  -> "Connecting": 1
  case .disconnecting -> "Disconnecting": 1
  case .disconnected -> "Disconnected": 1
  case .invalid -> "Invalid":        1
  literal "Reasserting" word:        0   ✅

DashboardView:
  monitor.effectiveInterfaceLabel:    1
  old monitor.currentInterfaceType.displayName: 0  ✅
  new toggle copy:                    1
  old toggle copy:                    0  ✅
  @AppStorage("omitLocationData"):    1
```

## Human UAT checklist (per Phase 7 precedent)

After phase completion, the user should run on iPhone 17 Pro Max / iOS 26.4.2:

1. Open Console.app, filter to subsystem `com.cellguard.connectivity`
   category `vpn`. Launch the app — confirm one `VPN self-check: keys=[…]`
   line appears with a matched prefix when ProtonVPN is enabled.
2. With VPN connected over cellular: open the dashboard, observe the
   "Interface" card now reads "VPN" instead of "Cellular".
3. Force a connectivity drop (airplane mode flick or carrier signal loss)
   while VPN is up: open the resulting event in the list, observe the new
   "VPN" section between "Wi-Fi" and "Probe" with `State: Connected` (or
   `Reconnecting` during the 5-second window after the drop).
4. Toggle "Omit location, Wi-Fi, and VPN data" on, export the event log
   via ShareLink, open the JSON: confirm no `vpnState` field appears on
   any event (Plan 02 encoder gate).
5. Toggle off, re-export: confirm `vpnState: "connected"` (or other
   non-trivial state) appears on events captured while the VPN was up.

## Hand-off

Wave 3 complete. Phase 8 closeout (verification, STATE.md / ROADMAP.md
updates) is the next step.
