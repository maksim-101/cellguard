# Phase 8: VPN Context - Context

**Gathered:** 2026-04-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Capture VPN tunnel state on every connectivity event, label VPN tunnels accurately in the UI (replacing the generic "Other" label), include VPN state in privacy-gated JSON export, and reclassify probe failures that occur during VPN handover as silent modem failures rather than generic probe failures.

Requirements covered: VPN-01, VPN-02, VPN-03, VPN-04.

</domain>

<decisions>
## Implementation Decisions

### VPN State Model

- **D-01:** Record the **full 6-state NEVPNStatus** (`invalid`, `disconnected`, `connecting`, `connected`, `reasserting`, `disconnecting`). The 3-state spec wording in VPN-01 (connected / disconnected / connecting) is satisfied as a UI projection of the richer underlying enum — the extra states (`reasserting` especially) carry diagnostic value for VPN-04 and for distinguishing "handover in progress" from "tunnel down" in the event log.
- **D-02:** Capture **VPN state only** — no tunnel name, no provider identifier, no localizedDescription. One new optional field on `ConnectivityEvent`. Matches VPN-01 literally and avoids a second privacy-gated field.
- **D-03:** Follow the established enum pattern — `Int` rawValue (with explicit values, never auto-increment) + `encodingString` (camelCase string for JSON export) + `fromEncodingString` (with backward-compat fallback) + `displayName` (human-readable for UI). Same shape as `EventType`, `PathStatus`, `InterfaceType`.

### UI Labeling

- **D-04:** Use a **computed display override** for the interface label — keep `interfaceType` raw (e.g., `.other`) in the SwiftData model so no schema migration is needed and no `.vpn` rawValue collision risk is introduced. Add a computed `effectiveInterfaceLabel` (or equivalent) that returns `"VPN"` when `vpnState ∈ {connected, reasserting}`. `DashboardView` and `EventDetailView` use this computed label instead of `interfaceType.displayName` directly.
- **D-05:** Show VPN state in EventDetailView via a **new conditional `Section("VPN")`** that mirrors the Phase 7 Wi-Fi section pattern. Section appears when `vpnState ∉ {disconnected, invalid}` (i.e. any non-trivial VPN activity). One LabeledContent row showing the displayName.

### Probe Reclassification (VPN-04)

> **D-06 SUPERSEDED 2026-04-25** — see Plan 03 BROAD-trigger override (user override during /gsd-plan-phase 8). Original narrow trigger preserved below as audit trail. The implemented behavior is: reclassify as `silentFailure` when (probe failed) AND (path satisfied) AND (effectively cellular), with `effectivelyCellular` covering any non-trivial VPN substate (`.connected | .reasserting | .connecting | .disconnecting`) over a cellular path. The narrow handover scenario is a strict subset of the broad rule.

- **D-06:** Reclassify a probe failure as `silentFailure` when **all** of the following hold:
  1. The probe failed (catch branch in `runProbe()`).
  2. `vpnState ∈ {connecting, reasserting}` at probe time (captured before await, same race-safety pattern as `capturedStatus`/`capturedInterface`).
  3. Effective transport is cellular — see D-07.
- **D-07:** Extend the silent-failure cellular check: treat `capturedInterface == .other` as cellular **if** a VPN is up AND `path.usesInterfaceType(.cellular) == true`. Without this, the silent-failure branch (the entire reason this app exists) is bypassed whenever any VPN tunnel is active, because `detectPrimaryInterface` returns `.other` for VPN tunnels.

### Privacy Gating

- **D-08:** VPN state is gated by the existing `omitLocation` userInfo flag (alongside `wifiSSID`, `latitude`, `longitude`, `locationAccuracy`) in `ConnectivityEvent.encode(to:)`. No new privacy flag — the toggle is a single privacy axis ("personal context off") and VPN choice is personal context. UI toggle copy may need updating to mention VPN (deferred to plan).

### Capture Timing

- **D-09:** VPN state capture follows the Phase 7 SSID precedent: if synchronous (NEVPNManager polling), capture **outside** the `Task` block in `logEvent`; if async, capture **inside** the `Task` block before SwiftData persistence. Final pattern depends on the detection mechanism research outcome (see Claude's Discretion below) — but the placement rule is fixed.

### Claude's Discretion

- **Detection mechanism** — `NEVPNManager.shared().connection.status` vs `NWPath.usesInterfaceType(.other)` vs hybrid. Researcher to determine: (a) whether NEVPNManager.shared() detects 3rd-party VPN apps (Mullvad, WireGuard, system VPN profiles) or only the calling app's tunnels, (b) whether `loadFromPreferences()` is required, (c) whether NEVPNManager fires KVO/notification on status changes or requires polling. The recorded enum and the silent-failure reclassification logic stay the same regardless.
- **Privacy toggle copy** — current label is "Omit location and Wi-Fi data". Whether/how to extend it to mention VPN is a small UX call left to the planner.
- **Live state binding** — whether to expose `currentVPNState` as `@Observable` private(set) on `ConnectivityMonitor` for live dashboard binding (parallel to `currentRadioTechnology`) or only stamp at event time. Planner decides based on whether the dashboard needs a live VPN indicator.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project specs
- `.planning/PROJECT.md` — Core value, constraints, key decisions through v1.2.
- `.planning/REQUIREMENTS.md` §VPN — VPN-01 through VPN-04 acceptance criteria.
- `.planning/ROADMAP.md` §"Phase 8: VPN Context" — Goal, success criteria, dependencies.

### Prior phase artifacts (patterns to follow)
- `.planning/phases/07-wifi-context/07-RESEARCH.md` — NetworkExtension import patterns, async metadata capture in Task block (mirror this for VPN).
- `.planning/phases/07-wifi-context/07-01-SUMMARY.md` — `Network.NWPath` disambiguation, sync-outside / async-inside Task pattern, privacy gating via `omitLocation` userInfo flag.
- `.planning/phases/07-wifi-context/07-PATTERNS.md` — established codebase conventions referenced during Phase 7.

### Codebase touchpoints
- `CellGuard/Models/ConnectivityEvent.swift` — `@Model` ConnectivityEvent + `Codable` extension. Add `vpnState` field, `VPNState` enum (rawValue + encodingString + fromEncodingString + displayName), encode/decode with `omitLocation` gating.
- `CellGuard/Services/ConnectivityMonitor.swift` — `runProbe()` (line ~225) for VPN-04 reclassification, `detectPrimaryInterface()` (line ~479) interaction with `.other`, `logEvent()` (line ~499) for capture timing. Already imports `NetworkExtension`.
- `CellGuard/Views/EventDetailView.swift` — `Section("Wi-Fi")` block (line 30) is the template for the new `Section("VPN")`. `InterfaceType.displayName` extension (line 110) is where the computed VPN-aware label hook will live (or in a new computed property on the event/monitor).
- `CellGuard/Views/DashboardView.swift` — `monitor.currentInterfaceType.displayName` (line 180) is the dashboard interface label that VPN-02 requires to display "VPN".

No external ADRs — requirements fully captured here and in REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **NetworkExtension framework already imported** in `ConnectivityMonitor.swift` (Phase 7 added it for `NEHotspotNetwork`). VPN APIs (`NEVPNManager`, `NEVPNStatus`) ship in the same framework — no new import, no new entitlement work expected.
- **`omitLocation` userInfo flag** on `ConnectivityEvent.encode(to:)` already gates SSID + location atomically. VPN state slots into the same `if !omitLocation { ... }` block.
- **`encodingString` / `fromEncodingString` / `displayName` enum pattern** — established for `EventType`, `PathStatus`, `InterfaceType`. New `VPNState` enum follows the exact same shape (Int raw + String encoding + UI display + backward-compat decode).
- **Phase 7 capture-timing pattern** in `logEvent()` — sync values (`radioTech`, `carrier`, `location`) captured outside the Task block; async value (`ssid`) captured inside the Task block before SwiftData persist. VPN state capture lands here using the same rule.
- **Race-safe probe pattern** in `runProbe()` — `capturedStatus`/`capturedInterface` snapshotted before `await`. VPN-04 needs the same: snapshot `vpnState` before awaiting the probe response, classify against the snapshot.

### Established Patterns

- **`Network.NWPath` qualification** required everywhere `NWPath` is referenced because `Network` and `NetworkExtension` both export the type. Continue using `Network.NWPath`.
- **No SwiftData migration needed for additive optional fields** — Phase 7 confirmed adding an optional `wifiSSID: String?` did not require a migration step. New optional `vpnStateRaw: Int?` should behave the same way.
- **Decode with String-first / Int-fallback** — every enum decoder tries the String encoding first, then falls back to Int for legacy export files. New `VPNState` decoder follows this.
- **500ms debounce on path changes** in `handlePathUpdate` — already absorbs flapping; VPN reasserting/connecting transitions that ride on path changes inherit this for free.

### Integration Points

- **`logEvent()` signature** — adding VPN state means a new (likely optional) parameter, plus a capture call. Touch every call site (4–5 in ConnectivityMonitor today).
- **`detectPrimaryInterface()`** — does NOT change shape; the VPN-aware logic lives in the silent-failure reclassification branch and the UI display layer, not in interface detection. Keeps `InterfaceType` enum stable (no `.vpn` case).
- **EventDetailView** — add one new conditional Section. EventListRow / DashboardView interface label use a new computed display helper.

</code_context>

<specifics>
## Specific Ideas

- The user explicitly preferred the **richer 6-state NEVPNStatus** even though VPN-01 only names 3 states — extra states (especially `reasserting`) carry diagnostic value for VPN-04. UI projects them down to the spec's 3 states; the model keeps them.
- For VPN-02 the user picked the **non-invasive computed override** path explicitly to avoid touching the SwiftData enum schema. This is the lowest-blast-radius option and preserves the existing `interfaceType` field as a faithful record of what NWPath reported.
- For VPN-04 the user picked the **strictest of the lower-false-positive options**: VPN connecting/reasserting + cellular path (D-06), AND extending the cellular check so VPN-over-cellular still triggers the silent-failure branch (D-07). The pair of decisions together fixes a latent gap where any VPN being up would otherwise mask all silent-failure detection.

</specifics>

<deferred>
## Deferred Ideas

- **Live VPN indicator on the dashboard** (e.g., a "VPN: connecting" pill alongside the radio tech display) — out of scope for VPN-01..VPN-04 as written. If wanted, belongs in Phase 9 (Dashboard Polish) or a future v1.4 phase.
- **Per-tunnel name capture** — explicitly deferred (D-02). If post-deployment data shows multiple VPN providers in use and we want to distinguish them, can add a future quick task.
- **MapKit visualization of drops vs VPN state** — out of scope; intersects with v1.3 Future Requirements (map view) and is a separate feature.
- **3rd-party VPN compatibility matrix** — if NEVPNManager turns out to only see the calling app's tunnels, the researcher may surface alternative APIs (NETunnelProviderManager, NWPathMonitor heuristics). Findings to be captured in RESEARCH.md, not as a new phase.

</deferred>

---

*Phase: 08-vpn-context*
*Context gathered: 2026-04-25*
