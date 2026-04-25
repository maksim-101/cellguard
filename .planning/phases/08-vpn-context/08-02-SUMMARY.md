---
phase: 08-vpn-context
plan: 02
type: execute
status: complete
created: 2026-04-25
updated: 2026-04-25
---

# Plan 08-02 Summary — VPN schema on `ConnectivityEvent`

## What was built

Mirrored the Phase 7 `wifiSSID` wiring line-for-line for VPN state. `CellGuard/Models/ConnectivityEvent.swift` now carries an optional `VPNState` field with a privacy-gated, string-encoded JSON representation.

## Edits made (all in `CellGuard/Models/ConnectivityEvent.swift`)

1. **`enum VPNState: Int, Codable`** added next to the other event enums (line 41–50). Six explicit raw values matching `NEVPNStatus`: `invalid=0, disconnected=1, connecting=2, connected=3, reasserting=4, disconnecting=5` (D-01 + D-03).
2. **`vpnStateRaw: Int?` storage + `vpnState: VPNState?` computed accessor** added in a new `// MARK: VPN metadata` section adjacent to `wifiSSID` (line 102–113). Optional storage — legacy events stay nil with no migration.
3. **Init parameter** `vpnState: VPNState? = nil` after `wifiSSID` (line 180), with `self.vpnStateRaw = vpnState?.rawValue` in the body (line 198).
4. **`case vpnState`** added to `CodingKeys` after `case wifiSSID` (line 228).
5. **Decode block** with String-first then Int-fallback semantics (line 261–270). Bare `try? container.decode` (not `decodeIfPresent`) — a missing key produces `nil` from `try?` which correctly maps to `vpnState = nil`. Threaded into `self.init(...)` after `wifiSSID:`.
6. **Encode block** extended inside the existing `if !omitLocation { ... }` block (line 313–315). Uses the UI-SPEC export filter: encodes only when `state != .disconnected && state != .invalid`, emitting `state.encodingString`.
7. **`extension VPNState`** with `encodingString` and `fromEncodingString` (line 379–404), placed right after the `InterfaceType` extension. Encoding strings are the lowercased `NEVPNStatus` enum names per UI-SPEC table.

## Encoding mapping (UI-SPEC reference)

| `VPNState` case | rawValue | `encodingString` | Exported? |
|---|---|---|---|
| `.invalid` | 0 | `"invalid"` | no (filtered) |
| `.disconnected` | 1 | `"disconnected"` | no (filtered) |
| `.connecting` | 2 | `"connecting"` | yes |
| `.connected` | 3 | `"connected"` | yes |
| `.reasserting` | 4 | `"reasserting"` | yes |
| `.disconnecting` | 5 | `"disconnecting"` | yes |

Privacy gate: even meaningful states (`.connecting`/`.connected`/`.reasserting`/`.disconnecting`) are omitted when `omitLocation == true` (the export setting that already strips lat/lon/SSID).

## Guards verified

- No `.vpn` case added to `InterfaceType` — D-04 holds.
- No `VersionedSchema` / `SchemaMigrationPlan` introduced — additive optional, lightweight migration handled by SwiftData.
- No `displayName` extension on `VPNState` in this file — that lives in `EventDetailView.swift` per Phase 7 convention (Plan 04).

## Build

`xcrun xcodebuild -scheme CellGuard -destination 'generic/platform=iOS' -configuration Debug build` → `** BUILD SUCCEEDED **`.

## Hand-off to Plan 03

- `VPNState` is referenceable as a typed identifier from `ConnectivityMonitor.swift`.
- `event.vpnState` returns `VPNState?`.
- `ConnectivityEvent.init(..., vpnState: ...)` accepts the new parameter; existing call sites compile unchanged because the parameter has a `nil` default.

## Self-Check: PASSED
