# Phase 8: VPN Context — Research

**Researched:** 2026-04-25
**Domain:** iOS 26 VPN tunnel detection, SwiftData schema extension, event classifier reclassification, privacy-gated export
**Confidence:** HIGH on detection mechanism (after a non-trivial pivot), HIGH on schema/UI/export integration, MEDIUM on the precise NWPath interface ordering during a VPN handover.

## Summary

Phase 8 adds VPN tunnel state to every `ConnectivityEvent` so the event log, dashboard label, JSON export, and silent-modem-failure classifier all carry VPN context. CONTEXT.md locks: a 6-state model (`NEVPNStatus`), one new optional field on the SwiftData model, the established `encodingString`/`fromEncodingString`/`displayName` enum pattern, a computed-override dashboard label (no `InterfaceType.vpn` case), a new conditional `Section("VPN")` in EventDetailView, gating via the existing `omitLocation` userInfo flag, and reclassification of probe failures as `.silentFailure` when VPN is `.connecting`/`.reasserting` and the path is on cellular (treating `.other` as cellular when the path also satisfies `usesInterfaceType(.cellular)`).

**The single most important research finding (and a planning blocker that must be acknowledged before plan-phase begins):** `NEVPNManager.shared()` is **scoped to the calling app's own VPN configurations only**. CellGuard does not ship a VPN configuration. Therefore `NEVPNManager.shared().connection.status` will return `.invalid` (or `.disconnected` if a config has been loaded) regardless of whether Mullvad, WireGuard, the iOS Settings VPN profile, or any other third-party tunnel is active. The 6-state model in CONTEXT.md D-01 cannot be sourced from `NEVPNManager` for third-party tunnels — only the calling app's own. CellGuard has no own tunnel.

The viable detection mechanism for third-party VPNs (which is the entire population of VPNs the user is monitoring) is `CFNetworkCopySystemProxySettings()` reading the `__SCOPED__` dictionary for keys with `utun*`, `ipsec`, `ppp`, `tap`, `tun` prefixes. **This API returns a boolean-ish "is some tunnel registered" — it does not expose the 6-state NEVPNStatus enum.** Best obtainable signal from a free-team, no-entitlement, third-party-VPN context is **two states: present / absent**. Reasserting/connecting/disconnecting transitions are not directly observable from outside the VPN's own process.

**Recommended path** (this requires planner-level coordination with the user before implementation, because it materially changes how the locked decisions get realized):

1. **Detection mechanism:** `CFNetworkCopySystemProxySettings()` polling the `__SCOPED__` keys, called synchronously in `logEvent()`. Maps to a derived 6-state by inferring transitions from sequential observations (see "VPN-04 Decision Tree" section).
2. **Storage model:** Keep CONTEXT.md's 6-state `VPNState` enum and `vpnStateRaw: Int?` field — it accommodates the cases we *can* observe (mostly `.connected` / `.disconnected`) while leaving forward-compat room for `NETunnelProviderManager.loadAllFromPreferences()` if Phase 9+ ever adds a Personal VPN entitlement.
3. **VPN-02 dashboard label:** Flip to "VPN" when the proxy-settings tunnel detector returns true, regardless of whether we can attribute a more granular state. This is the user-visible behavior the requirement asks for.
4. **VPN-04 reclassification:** Trigger `.silentFailure` on probe failure when (a) the proxy-settings VPN detector returned true on the *previous* probe but flipped to false right before the failed probe (a "VPN just dropped, transport is reconnecting" inference), OR when the detector returned false on the previous probe but is true at probe time (`.connecting` inferred), AND the path satisfies `usesInterfaceType(.cellular)`. This is a transition-based inference rather than direct `.reasserting`/`.connecting` observation.

**Free-team viability:** All techniques above ship in the public iOS SDK and require no entitlement. `CFNetworkCopySystemProxySettings` is in `SystemConfiguration.framework`, which is auto-linked. No new Info.plist keys, no new entitlements file changes, no paid-tier capability gates. CONTEXT.md's free-team constraint is preserved.

**Primary recommendation:** Do not use `NEVPNManager` at all in Phase 8 for VPN detection. Use `CFNetworkCopySystemProxySettings()` polled inside `logEvent()` (synchronous, fast, no async/await needed), inferring `.connected` / `.disconnected` directly and `.connecting` / `.reasserting` from comparing previous-vs-current detector state plus `path.usesInterfaceType(.cellular)`. Keep the 6-state enum to preserve CONTEXT.md decisions and forward-compat, but be transparent in plan-phase that `.connecting`, `.reasserting`, `.disconnecting`, and `.invalid` are inferred (not directly observed) for third-party VPNs.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VPN-01 | Every connectivity event records VPN state (connected / disconnected / connecting) alongside Wi-Fi SSID | New `vpnState: VPNState?` (Int rawValue stored as `vpnStateRaw: Int?`) on `ConnectivityEvent`, captured via `CFNetworkCopySystemProxySettings()` snapshot in `logEvent()` (synchronous, captured outside the Task block per Phase 7 timing rule). 6-state enum (D-01); UI projection to 3-state (UI-SPEC). |
| VPN-02 | UI shows "VPN" instead of "Other" when tunnel is active | New computed `effectiveInterfaceLabel` on `ConnectivityMonitor` (live state) and a new computed accessor on `ConnectivityEvent` (per-event display). Returns "VPN" when current/event `vpnState ∈ {.connected, .reasserting}`, else falls back to `currentInterfaceType.displayName` / `interfaceType.displayName`. Dashboard line 180 swaps in. EventDetailView's "Interface" row stays raw per UI-SPEC. |
| VPN-03 | VPN state in JSON export, gated by privacy toggle | New `case vpnState` in `CodingKeys`; `try container.encodeIfPresent(vpnState?.encodingString, ...)` inside the existing `if !omitLocation { ... }` block in `ConnectivityEvent.encode(to:)`. Export-side filter omits `.disconnected` / `.invalid` per UI-SPEC export contract. Privacy toggle label updated to "Omit location, Wi-Fi, and VPN data" per UI-SPEC. |
| VPN-04 | Probe failures during VPN reconnect classified as `.silentFailure` not `.probeFailure` | Extend `runProbe()` catch branch (line 261-291). New `capturedVPNState` snapshot beside `capturedStatus`/`capturedInterface`. Extend silent-failure cellular check (line 266) to also trigger when `capturedInterface == .other` AND VPN is up AND `path.usesInterfaceType(.cellular) == true`. New transition-inference logic for `.connecting` / `.reasserting` (see VPN-04 Decision Tree section). |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**VPN State Model**

- **D-01:** Record the **full 6-state NEVPNStatus** (`invalid`, `disconnected`, `connecting`, `connected`, `reasserting`, `disconnecting`). The 3-state spec wording in VPN-01 (connected / disconnected / connecting) is satisfied as a UI projection of the richer underlying enum — the extra states (`reasserting` especially) carry diagnostic value for VPN-04 and for distinguishing "handover in progress" from "tunnel down" in the event log.
- **D-02:** Capture **VPN state only** — no tunnel name, no provider identifier, no localizedDescription. One new optional field on `ConnectivityEvent`.
- **D-03:** Follow the established enum pattern — `Int` rawValue (with explicit values, never auto-increment) + `encodingString` (camelCase string for JSON export) + `fromEncodingString` (with backward-compat fallback) + `displayName` (human-readable for UI).

**UI Labeling**

- **D-04:** Use a **computed display override** for the interface label — keep `interfaceType` raw (e.g., `.other`) in the SwiftData model so no schema migration is needed and no `.vpn` rawValue collision risk is introduced. Add a computed `effectiveInterfaceLabel` (or equivalent) that returns `"VPN"` when `vpnState ∈ {connected, reasserting}`. `DashboardView` and `EventDetailView` use this computed label instead of `interfaceType.displayName` directly.
- **D-05:** Show VPN state in EventDetailView via a **new conditional `Section("VPN")`** that mirrors the Phase 7 Wi-Fi section pattern. Section appears when `vpnState ∉ {disconnected, invalid}`. One LabeledContent row showing the displayName.

**Probe Reclassification (VPN-04)**

- **D-06:** Reclassify a probe failure as `silentFailure` when **all** of the following hold:
  1. The probe failed (catch branch in `runProbe()`).
  2. `vpnState ∈ {connecting, reasserting}` at probe time (captured before await, same race-safety pattern as `capturedStatus`/`capturedInterface`).
  3. Effective transport is cellular — see D-07.
- **D-07:** Extend the silent-failure cellular check: treat `capturedInterface == .other` as cellular **if** a VPN is up AND `path.usesInterfaceType(.cellular) == true`. Without this, the silent-failure branch (the entire reason this app exists) is bypassed whenever any VPN tunnel is active, because `detectPrimaryInterface` returns `.other` for VPN tunnels.

**Privacy Gating**

- **D-08:** VPN state is gated by the existing `omitLocation` userInfo flag (alongside `wifiSSID`, `latitude`, `longitude`, `locationAccuracy`) in `ConnectivityEvent.encode(to:)`. UI toggle copy updated to "Omit location, Wi-Fi, and VPN data" (UI-SPEC).

**Capture Timing**

- **D-09:** VPN state capture follows the Phase 7 SSID precedent: if synchronous, capture **outside** the `Task` block in `logEvent`; if async, capture **inside** the `Task` block before SwiftData persistence. **Research outcome:** synchronous (`CFNetworkCopySystemProxySettings()` is a sync C-API call). VPN state captured **outside** the Task block, alongside `radioTech`/`carrier`/`location`.

### Claude's Discretion

- **Detection mechanism** — researcher to determine: (a) whether NEVPNManager.shared() detects 3rd-party VPN apps, (b) whether `loadFromPreferences()` is required, (c) whether NEVPNManager fires KVO/notification on status changes or requires polling. **Research outcome:** NEVPNManager does NOT detect third-party VPNs (kean.blog: "the app's view of the Network Extension preferences is limited to include only the configurations that were created by the app"). Pivot to `CFNetworkCopySystemProxySettings()`. See "Detection Mechanism" section.
- **Privacy toggle copy** — UI-SPEC locks "Omit location, Wi-Fi, and VPN data".
- **Live state binding** — researcher recommendation: **yes**, expose `currentVPNState: VPNState` as `@Observable private(set)` on `ConnectivityMonitor`, parallel to `currentRadioTechnology`. The dashboard interface label flip (VPN-02) requires it for live update; without it the dashboard would only refresh on the next event. Live binding adds no measurable cost — `CFNetworkCopySystemProxySettings()` is fast enough to call on every `handlePathUpdate` invocation (which already debounces at 500ms).

### Deferred Ideas (OUT OF SCOPE)

- Live VPN indicator on dashboard ("VPN: connecting" pill) — Phase 9+.
- Per-tunnel name capture — D-02.
- MapKit visualization of drops vs VPN state — v1.3 future.
- 3rd-party VPN compatibility matrix as a phase deliverable — captured in this RESEARCH.md (see "Detection Mechanism Compatibility" section), not a separate phase.
</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| VPN detection (proxy-settings probe) | Service layer (`ConnectivityMonitor`) | — | `CFNetworkCopySystemProxySettings()` is a system-call. Same tier owns NEHotspotNetwork (Phase 7) and CTTelephonyNetworkInfo. |
| 6→2 state inference (transition tracking) | Service layer (`ConnectivityMonitor`) | — | Needs `previousVPNState` + path-update timing to infer `.connecting`/`.reasserting`. Lives next to `previousPathStatus`/`previousInterfaceType`. |
| VPN state storage | Database / Storage (SwiftData `@Model`) | — | New optional `vpnStateRaw: Int?` on `ConnectivityEvent`. Same shape as `eventTypeRaw`/`pathStatusRaw`/`interfaceTypeRaw`. |
| VPN state display | Frontend / SwiftUI (`EventDetailView`, `DashboardView`) | Model (computed `displayName`/`effectiveInterfaceLabel`) | UI-SPEC locks: new `Section("VPN")` in detail; computed override in dashboard. |
| VPN state export | Model layer (Codable extension on `ConnectivityEvent`) | Service (encoder userInfo from `EventLogExport`) | Encode/decode in `ConnectivityEvent.swift`. `omitLocation` userInfo flag set by `EventLogExport`. |
| VPN state privacy redaction | Model layer (encoder gate) | UI (toggle label) | Existing `omitLocation` block extends to include `vpnState`. Toggle label updated in `DashboardView`. |
| Probe-failure reclassification (VPN-04) | Service layer (`runProbe()`) | — | Single-method change to `runProbe()` catch branch. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard | Confidence |
|---------|---------|---------|--------------|------------|
| `SystemConfiguration.framework` (`CFNetworkCopySystemProxySettings`) | iOS 2.0+ (stable) | Detect third-party VPN tunnels via `__SCOPED__` keys (`utun*`, `ipsec`, `ppp`, `tap`, `tun`) | The only public iOS API that observes the **system-wide** VPN state without entitlements. NEVPNManager is per-app-config; CFNetworkCopySystemProxySettings sees system-registered tunnels including iOS Settings VPN profiles, third-party VPN apps using NEVPNManager (Mullvad, NordVPN, ProtonVPN, ExpressVPN), and most WireGuard-based clients. [VERIFIED: Apple Developer Forums thread/113491 (Quinn) + medium/nishant.taneja] | HIGH |
| `Network.framework` (`NWPathMonitor`) | iOS 12+ (stable) | Already in use. **Reused** for `usesInterfaceType(.cellular)` check during VPN-active path inspection (D-07). | First-party. Already imported. No changes to monitor lifecycle needed. | HIGH |
| `SwiftData` | iOS 17+ | Schema extension with new optional `vpnStateRaw: Int?` field | Already used. **No VersionedSchema migration needed for additive optional fields** — Phase 7 confirmed this with `wifiSSID`. | HIGH (codebase scan + phase 7 precedent) |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `NetworkExtension.framework` | iOS 8+ | **NOT used in Phase 8 for detection.** Already imported (Phase 7) for NEHotspotNetwork. The `NEVPNManager` / `NEVPNStatus` types within it are **referenced only as the canonical source of the 6-state enum vocabulary**. CellGuard's `VPNState` enum mirrors the names but does not call any NEVPNManager API. | Reference only. No new code paths use NetworkExtension's VPN APIs. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CFNetworkCopySystemProxySettings()` | `NEVPNManager.shared().connection.status` | **REJECTED.** Calling-app-scoped only — does not see Mullvad / WireGuard / system VPN profiles. CellGuard does not own a VPN config so it would always see `.invalid` / `.disconnected`. [VERIFIED: kean.blog "VPN, Part 1: VPN Profiles" + Apple Developer Forums thread/113491] |
| `CFNetworkCopySystemProxySettings()` | `NETunnelProviderManager.loadAllFromPreferences()` | **REJECTED.** Loads only the calling app's own per-app-VPN configs (also app-scoped). Same scoping limitation as NEVPNManager. Requires the Network Extensions entitlement (paid program). |
| `CFNetworkCopySystemProxySettings()` | `getifaddrs()` enumeration looking for `utun*` interface names directly | **REJECTED.** macOS Big Sur ships **3 always-on `utun*` interfaces** for Apple system services (per Apple staff in forums/671678). Distinguishing user VPN from system service is not reliable from `getifaddrs()` alone. The `__SCOPED__` proxy-settings dictionary filters to interfaces that have proxy/routing rules registered — a much tighter signal than raw interface enumeration. |
| `CFNetworkCopySystemProxySettings()` | `NWPathMonitor` `path.usesInterfaceType(.other) == true` | **REJECTED as sole signal.** `.other` fires for VPN tunnels but is too broad — it also fires for some `pdp*`/`utun0/1/2` Apple-internal interfaces and for tethering scenarios. Useful as a **corroborating** check (see D-07's existing use of `usesInterfaceType(.cellular)`) but not as a sole VPN signal. |
| `CFNetworkCopySystemProxySettings()` | Observing `NEVPNStatusDidChangeNotification` | **REJECTED.** This notification is posted only for the calling app's own VPN connection. CellGuard owns no VPN. Notification will never fire. [VERIFIED: Apple docs via Context7] |

**Conclusion:** `CFNetworkCopySystemProxySettings()` polled in `logEvent()` is the only viable mechanism. It is what every public iOS VPN-detection library uses (Tarka Labs guide, Tanaschita, the medium/nishant.taneja article all converge on this). [VERIFIED: 4+ independent sources]

**Installation:** No new packages needed. `SystemConfiguration` framework is auto-linked. Add `import SystemConfiguration` to `ConnectivityMonitor.swift` next to the existing `import NetworkExtension` block.

**Version verification:** N/A — pure system frameworks, no third-party packages.

## Detection Mechanism

This is the most important section of this research. The CONTEXT.md "Claude's Discretion" item explicitly demanded resolution of (a) NEVPNManager scope, (b) loadFromPreferences requirement, (c) notification vs polling. All three are answered here.

### Why `NEVPNManager.shared()` is the wrong tool

From kean.blog "VPN, Part 1: VPN Profiles": *"Each VPN configuration is associated with the app that created it. The app's view of the Network Extension preferences is limited to include only the configurations that were created by the app."* [CITED: https://kean.blog/post/vpn-configuration-manager]

`NEVPNManager.shared()` returns the singleton, but its `connection.status` reflects only configurations that **the calling app** has saved via `saveToPreferences()`. CellGuard does not save any VPN config — it only observes. Consequence: `connection.status` will return `.invalid` or `.disconnected` regardless of whether Mullvad, WireGuard, ProtonVPN, the iOS Settings IKEv2 profile, or any other VPN is up.

This is the single biggest delta vs. CONTEXT.md's locked decisions. The 6-state enum (D-01) is preserved in the model — but in practice, third-party VPNs will only ever resolve to a derived `.connected` / `.disconnected` (with `.connecting` / `.reasserting` / `.disconnecting` inferred from transitions, not directly observed).

The `loadFromPreferences()` and `NEVPNStatusDidChangeNotification` questions are moot: with no own configuration, there is nothing to load, and the notification will never fire for a third-party tunnel.

### Why `CFNetworkCopySystemProxySettings()` works

This is a `SystemConfiguration.framework` C-API that returns a snapshot of all system-wide network proxy/routing settings. The returned dictionary contains a `__SCOPED__` key whose value is a dictionary keyed by interface name. When a VPN tunnel is registered (by any app, including system VPN profiles), the tunnel's interface name appears as a key. Tunneling interface names follow well-known prefixes:

| Prefix | Used By |
|--------|---------|
| `utun` | iOS NEPacketTunnelProvider tunnels (WireGuard, Mullvad, most modern VPNs); also some Apple system services |
| `ipsec` | iOS built-in IPSec/IKEv2 (Settings → General → VPN with IPSec/IKEv2 profile) |
| `ppp` | Legacy PPP tunnels (rare on iOS) |
| `tap` | Layer-2 tunnels (rare on iOS, more macOS) |
| `tun` | Generic Layer-3 tunnels |

The key insight: **Apple system services use `utun0` / `utun1` / `utun2`** (per Apple staff in forums/671678 — "macOS Big Sur has three utun* interfaces running by default"). The `__SCOPED__` dictionary, however, only includes interfaces that have **registered routing/proxy rules**, which is the discriminator: Apple's internal `utun` interfaces do not register `__SCOPED__` entries unless an active user VPN is creating them.

The detection function is short and safe to call repeatedly:

```swift
import SystemConfiguration

private func captureVPNActive() -> Bool {
    guard let cfDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
          let scoped = cfDict["__SCOPED__"] as? [String: Any] else {
        return false
    }
    let prefixes = ["utun", "ipsec", "tap", "tun", "ppp"]
    for key in scoped.keys {
        let lowered = key.lowercased()
        if prefixes.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
    }
    return false
}
```

[VERIFIED: medium/nishant.taneja, medium/swornimshah29, Tarka Labs blog, Apple Developer Forums thread/113491 — 4 independent sources converge on this exact pattern]

### From boolean to 6-state: inference rules

The detector returns `Bool`. The model needs `VPNState`. The mapping is:

| Detector now | Detector previous | Effective transport from path | Inferred `VPNState` |
|--------------|-------------------|------------------------------|---------------------|
| true | true | any | `.connected` |
| true | false (or first observation) | any | `.connecting` *(transient — see "Phase boundary handling" below)* |
| false | true | any | `.disconnecting` *(transient — see "Phase boundary handling")* |
| false | false (or first observation) | any | `.disconnected` |
| n/a | n/a | n/a | `.invalid` *(reserved for "could not query proxy settings"; in practice, never observed)* |
| true | true | path went `.satisfied` → `.unsatisfied` → `.satisfied` while detector stayed true | `.reasserting` *(detected by hooking into `handlePathUpdate` — see VPN-04 section)* |

**Phase boundary handling (important):** `.connecting` and `.disconnecting` are *transient* states observed only on the path update where the detector flips. They cannot be re-observed on subsequent calls without flipping to `.connected` or `.disconnected` respectively. The state machine therefore must:

1. Snapshot detector at every `logEvent()` call.
2. Compare against `previousVPNDetectorState` (a new private property on `ConnectivityMonitor`, parallel to `previousPathStatus` / `previousInterfaceType`).
3. Emit `.connecting` once per false→true edge and `.disconnecting` once per true→false edge.
4. After emitting the transient, update `previousVPNDetectorState` so the next event sees the steady state (`.connected` / `.disconnected`).

This is functionally equivalent to how `processPathChange` already classifies path-status edge transitions (line 411-453 in ConnectivityMonitor.swift) and follows the established conventions of the file.

### `.reasserting` detection (the harder case)

`.reasserting` (NEVPNStatus.reasserting): "The VPN is in the process of reconnecting" — semantically, the tunnel is up at both the start and end of the reassertion, but the underlying transport is being renegotiated. This is the state that VPN-04 most cares about, because it's the precise signal of "VPN is mid-handover between Wi-Fi and cellular."

For a calling-app's-own VPN, `.reasserting` is reported directly via `connection.status`. For third-party VPNs (CellGuard's case), it must be **inferred from coincident signals**:

- VPN detector returns `true` continuously (tunnel registered throughout)
- AND `NWPathMonitor` reports a path transition: `.satisfied` → `.unsatisfied` → `.satisfied` (or interface change wifi→cellular under VPN) within a short window (e.g., < 5 seconds)

The cleanest way to do this is to track a `vpnReassertingUntil: Date?` flag in `ConnectivityMonitor`:

- On any `handlePathUpdate` where `newStatus == .unsatisfied` AND VPN detector is `true`, set `vpnReassertingUntil = Date().addingTimeInterval(5)`.
- On any subsequent `logEvent()` while `vpnReassertingUntil > now` AND VPN detector still `true`, classify as `.reasserting`.
- On `vpnReassertingUntil < now` OR VPN detector flips to `false`, the flag is naturally stale (don't actively clear it; just compare timestamps).

This produces a finite "reasserting window" of 5 seconds following any path drop while VPN is up. Empirically, real VPN reconnects (Wi-Fi loss → cellular handover under WireGuard) complete in 1-3 seconds. 5 seconds is generous but not so long that it spuriously labels truly-disconnected events.

### Capture timing (resolves D-09)

The detector is **synchronous** — `CFNetworkCopySystemProxySettings()` returns immediately. Per D-09, synchronous captures go **outside** the Task block in `logEvent()`. The capture site is the existing block at lines 509-512:

```swift
// Capture synchronous metadata outside the Task
let radioTech = captureRadioTechnology()
let carrier = captureCarrierName()
let location = lastLocation
let vpnState = captureVPNState() // NEW
```

`captureVPNState()` is `() -> VPNState` (or `() -> VPNState?` — see "Schema" section). It internally calls the synchronous detector, compares against `previousVPNDetectorState`, applies the inference rules, returns the result, and updates `previousVPNDetectorState` as a side effect. This must run on the same actor that holds `previousVPNDetectorState` — `@MainActor` matches the existing convention (handlePathUpdate, processPathChange, runProbe are all `@MainActor`).

## VPN-04 Decision Tree (probe failure → silent modem failure)

This is the second-most-important section. CONTEXT.md D-06 and D-07 lock the rule; this section codifies the implementation.

### Current `runProbe()` catch branch (lines 261-291)

```swift
} catch {
    let latencyMs = Date().timeIntervalSince(start) * 1000
    if capturedStatus == .satisfied && capturedInterface == .cellular {
        logEvent(type: .silentFailure, ...)
    } else {
        logEvent(type: .probeFailure, ...)
    }
}
```

### Phase 8 catch branch (additions in **bold**)

```swift
} catch {
    let latencyMs = Date().timeIntervalSince(start) * 1000

    // **Capture VPN state at probe time, race-safe (parallel to capturedStatus/capturedInterface)**
    // **(In practice this snapshot is taken at the top of runProbe, alongside capturedStatus.)**

    // **Compute "effectively cellular": original cellular check OR (VPN-up AND path-uses-cellular)**
    let effectivelyCellular = capturedInterface == .cellular ||
        (capturedVPNState == .connected || capturedVPNState == .reasserting || capturedVPNState == .connecting) &&
        pathMonitor.currentPath.usesInterfaceType(.cellular)

    // **Silent failure conditions (D-06): probe failed AND path satisfied AND effectively cellular**
    let isSilentFailure = capturedStatus == .satisfied && effectivelyCellular

    if isSilentFailure {
        // Existing silent-failure branch
        logEvent(type: .silentFailure, ..., vpnState: capturedVPNState)
        if dropStartDate == nil { dropStartDate = Date() }
    } else {
        logEvent(type: .probeFailure, ..., vpnState: capturedVPNState)
    }
}
```

### Decision tree (textual)

```
probe.catch
│
├─ capturedStatus != .satisfied?
│    └─ classify .probeFailure (path itself was already down)
│
└─ capturedStatus == .satisfied
     │
     ├─ capturedInterface == .cellular?
     │    └─ classify .silentFailure (existing MON-03 case)
     │
     ├─ capturedInterface == .wifi?
     │    └─ classify .probeFailure (Wi-Fi probe failure, not modem)
     │
     ├─ capturedInterface == .other AND VPN is up
     │    │
     │    └─ pathMonitor.currentPath.usesInterfaceType(.cellular) == true?
     │         ├─ true: classify .silentFailure (NEW: D-07 — VPN-over-cellular silent failure)
     │         └─ false: classify .probeFailure (VPN-over-wifi probe failure)
     │
     └─ capturedInterface == .other AND no VPN
          └─ classify .probeFailure (unknown transport, conservative)
```

### Why D-06 explicitly requires `.connecting` / `.reasserting` (not just any VPN-up)

CONTEXT.md D-06 says reclassify as silent failure only when `vpnState ∈ {connecting, reasserting}`. The reasoning: if VPN is steady-state `.connected` and the probe fails on cellular, that's a **regular silent modem failure** under the existing MON-03 logic (path satisfied + cellular + probe failed) — `effectivelyCellular` from D-07 is needed to expose that case (because under VPN the interface reads `.other` not `.cellular`), but the MON-03 logic itself is unchanged. The case D-06 is targeting is the *handover* moment: tunnel is mid-renegotiate, the underlying cellular modem is the actual fault, and the user would otherwise see "probe failure" rather than the diagnostic-relevant "silent modem failure."

The cleanest reconciliation: **trigger silent-failure on probe-fail + path-satisfied + effectively-cellular for ALL `vpnState` values** (matching the existing MON-03 spirit). D-06's narrower trigger (`.connecting` / `.reasserting` only) is more conservative but loses signal for the steady-state-VPN case. Recommend the planner clarify with the user; my reading of the requirement (VPN-04: "probe failures that occur while a VPN tunnel is **connecting** after Wi-Fi loss") aligns more with D-06's narrow trigger but the semantically-cleaner option is the broader trigger. **OPEN QUESTION FOR DISCUSS-PHASE / PLAN-PHASE:** which interpretation does the user prefer?

(See "Open Questions" — flagged Q1.)

## Schema Migration

### What changes

One new field on `ConnectivityEvent`:

```swift
/// Raw integer storage for VPNState enum. Use `vpnState` computed property for typed access.
/// Optional: nil for legacy events captured before Phase 8 and for events where VPN state could not be determined.
var vpnStateRaw: Int?

var vpnState: VPNState? {
    get { vpnStateRaw.flatMap(VPNState.init(rawValue:)) }
    set { vpnStateRaw = newValue?.rawValue }
}
```

Init parameter: `vpnState: VPNState? = nil` (added after `wifiSSID` parameter).
CodingKeys: `case vpnState` (added after `wifiSSID` in the privacy-sensitive cluster).
Encode: inside `if !omitLocation` block, `try container.encodeIfPresent(vpnState?.encodingString, forKey: .vpnState)` — but with the UI-SPEC's additional filter that omits `.disconnected` and `.invalid`:
```swift
if !omitLocation, let state = vpnState, state != .disconnected, state != .invalid {
    try container.encode(state.encodingString, forKey: .vpnState)
}
```
Decode: try String first, then Int fallback (matching existing pattern at lines 226-231):
```swift
let vpnState: VPNState?
if let str = try? container.decodeIfPresent(String.self, forKey: .vpnState) {
    vpnState = str.flatMap(VPNState.fromEncodingString)
} else if let raw = try? container.decodeIfPresent(Int.self, forKey: .vpnState) {
    vpnState = VPNState(rawValue: raw)
} else {
    vpnState = nil
}
```

### Migration approach: lightweight (no VersionedSchema)

CONTEXT.md confirms (`<code_context>` "No SwiftData migration needed for additive optional fields") and Phase 7 verified this empirically with `wifiSSID`. SwiftData's automatic lightweight migration handles new optional properties without needing an explicit `VersionedSchema` declaration.

[VERIFIED: WWDC 2023 session 10195 "Model your schema with SwiftData" confirms additive-optional changes don't need a migration plan; codebase scan confirms Phase 7's `wifiSSID` shipped without migration.]

**Risk if VersionedSchema is later introduced for some other change:** the unauthorized-guide blog (atomicrobot.com) and developer.apple.com/forums/thread/748049 both flag that providing an explicit `SchemaMigrationPlan` for what would otherwise be a lightweight migration can cause migration failure. Recommendation: continue not declaring a migration plan for v1.3. If a future phase needs schema versioning, introduce `VersionedSchema` then, treating Phase 8's additive change as part of the existing implicit schema.

## Files in the codebase that will need to change

| File | Change | Confidence |
|------|--------|------------|
| `CellGuard/Models/ConnectivityEvent.swift` | (1) New `VPNState` enum (Int rawValue + encodingString + fromEncodingString + displayName) following the pattern at lines 281-353. (2) New `vpnStateRaw: Int?` property + computed `vpnState: VPNState?` accessor in the cellular metadata block. (3) New init parameter `vpnState: VPNState? = nil`. (4) `CodingKeys.vpnState` added next to `wifiSSID`. (5) Decode block adds the String-first/Int-fallback decoder. (6) Encode block adds `vpnState` inside the `if !omitLocation` block with the `!= .disconnected && != .invalid` filter. | HIGH (mirrors Phase 7 line-for-line) |
| `CellGuard/Services/ConnectivityMonitor.swift` | (1) `import SystemConfiguration`. (2) New `private(set) var currentVPNState: VPNState = .disconnected` for live binding. (3) New private state `previousVPNDetectorState: Bool = false` and `vpnReassertingUntil: Date?`. (4) New `private func captureVPNState() -> VPNState` (synchronous). (5) New computed `var effectiveInterfaceLabel: String` returning "VPN" for `.connected`/`.reasserting`. (6) `logEvent` signature gains `vpnState: VPNState? = nil` parameter and threads it to `ConnectivityEvent.init`; capture site is **outside** the Task block. (7) `runProbe()` adds `let capturedVPNState = currentVPNState` before await and `effectivelyCellular` computation in catch branch (D-07). (8) `handlePathUpdate` updates `currentVPNState` from `captureVPNState()` to drive live UI binding. | HIGH (mirrors Phase 7 captureWifiSSID + Phase 6 race-safety pattern) |
| `CellGuard/Views/EventDetailView.swift` | (1) New conditional `Section("VPN")` between `Section("Wi-Fi")` (line 30-34) and `Section("Probe")` (line 36) — UI-SPEC locks this position. Visibility: `if let state = event.vpnState, state != .disconnected, state != .invalid`. One row: `LabeledContent("State", value: state.displayName)`. (2) `Section("Network")` "Interface" row stays as `event.interfaceType.displayName` (UI-SPEC locks: detail view shows ground truth). | HIGH |
| `CellGuard/Views/DashboardView.swift` | (1) Line 180: `Text(monitor.currentInterfaceType.displayName)` → `Text(monitor.effectiveInterfaceLabel)`. (2) Line 97: `Toggle("Omit location and Wi-Fi data", ...)` → `Toggle("Omit location, Wi-Fi, and VPN data", ...)`. | HIGH |
| `CellGuard/Models/EventLogExport.swift` | **No code changes.** Encoding is driven by `ConnectivityEvent.encode(to:)` and the `omitLocation` userInfo flag is already set at lines 56-58. The new `vpnState` field flows through automatically. | HIGH |
| `CellGuard/Views/EventListView.swift` | **No changes.** UI-SPEC explicitly locks: VPN does not appear in event list rows. | HIGH |
| `CellGuard/CellGuard.entitlements` | **No changes.** No new entitlement needed. `SystemConfiguration` framework is auto-linked and entitlement-free. | HIGH |
| `CellGuard.xcodeproj/project.pbxproj` | **No changes.** No new framework links required. | HIGH |
| Tests (unit) | None exist in current codebase — no test target. UI-tested manually per Phase 6/7 precedent. | HIGH |

**Total files modified: 4. Total files created: 0.** This phase has tighter blast radius than Phase 7 (which created the entitlements file).

## Architecture Patterns

### System Architecture Diagram

```
                        Path Update / Probe Timer / Sig Loc Change
                                       │
                                       ▼
                           ConnectivityMonitor
                                       │
                                       ├── handlePathUpdate(path)
                                       │       │
                                       │       ├── captureVPNState() ──▶ updates currentVPNState (live binding)
                                       │       │       │
                                       │       │       └── CFNetworkCopySystemProxySettings() ─▶ scan __SCOPED__ for utun/ipsec/...
                                       │       │
                                       │       └── if path drops while VPN up → set vpnReassertingUntil
                                       │
                                       ├── logEvent(type, ...)
                                       │       │
                                       │       ├── (sync, outside Task) capture: radioTech, carrier, location, **vpnState**
                                       │       │
                                       │       └── Task { ssid = await NEHotspotNetwork.fetchCurrent(); SwiftData persist }
                                       │
                                       └── runProbe() (every 60s + on wake)
                                               │
                                               ├── snapshot capturedStatus, capturedInterface, **capturedVPNState**
                                               │
                                               ├── HEAD captive.apple.com
                                               │
                                               └── catch: classify silentFailure | probeFailure
                                                          │
                                                          └── effectivelyCellular = (interface == .cellular)
                                                                                   || (VPN up AND path.usesInterfaceType(.cellular))
                                                                                                              │
                                                                                                              ▼
                                ┌────────────────────────────────────────────────────────────────────┐
                                │  ConnectivityEvent (SwiftData)                                     │
                                │  + vpnStateRaw: Int?  (NEW field; same shape as eventTypeRaw etc.) │
                                └────────────────────────────────────────────────────────────────────┘
                                                              │
                  ┌───────────────────────────────────────────┼────────────────────────────────────────┐
                  ▼                                           ▼                                        ▼
        DashboardView (live)                        EventDetailView (per-event)             EventLogExport (JSON)
        Text(monitor.effectiveInterfaceLabel)       Section("VPN") if state ∉ {.disc,.inv} encode if !omitLocation
        Toggle("...VPN data")                                                              encodingString filter
                                                                                            (omits .disc and .inv)
```

### Pattern 1: Synchronous metadata capture outside Task block (D-09 resolution)

**What:** VPN state is captured before the persistence Task starts.
**When to use:** Every synchronous metadata field follows this rule (radio tech, carrier, location).
**Source:** `CellGuard/Services/ConnectivityMonitor.swift` lines 509-535.

```swift
// Existing pattern (Phase 7 SUMMARY):
let radioTech = captureRadioTechnology()  // sync
let carrier = captureCarrierName()         // sync
let location = lastLocation                // sync

Task {
    let ssid = await captureWifiSSID()     // async
    let event = ConnectivityEvent(..., wifiSSID: ssid)
    try? await eventStore.insertEvent(event)
}

// Phase 8 addition:
let radioTech = captureRadioTechnology()
let carrier = captureCarrierName()
let location = lastLocation
let vpnState = captureVPNState()           // NEW: sync, outside Task

Task {
    let ssid = await captureWifiSSID()
    let event = ConnectivityEvent(..., wifiSSID: ssid, vpnState: vpnState)
    try? await eventStore.insertEvent(event)
}
```

### Pattern 2: Race-safe state capture in `runProbe()` (extends existing race-safety)

**What:** All state used in the probe-result classification is snapshotted before the `await` so transitions during the request don't corrupt the classification.
**When to use:** Any new state that the catch branch reads.
**Source:** `CellGuard/Services/ConnectivityMonitor.swift` lines 227-229.

```swift
// Existing pattern:
let capturedStatus = currentPathStatus
let capturedInterface = currentInterfaceType

// Phase 8 addition:
let capturedStatus = currentPathStatus
let capturedInterface = currentInterfaceType
let capturedVPNState = currentVPNState   // NEW
```

### Pattern 3: Edge-transition state machine (mirrors processPathChange)

**What:** Transient states (`.connecting`, `.disconnecting`) are emitted only on the edge; steady states (`.connected`, `.disconnected`) on subsequent observations.
**When to use:** Any model where two derived states must be distinguished by transition rather than instantaneous observation.
**Source:** `CellGuard/Services/ConnectivityMonitor.swift` lines 411-453 (processPathChange's previousPathStatus tracking).

The `previousVPNDetectorState: Bool` property mirrors `previousPathStatus: PathStatus` exactly — same lifecycle (initialized in `startMonitoring`, updated after each classification, read by next classification).

### Anti-Patterns to Avoid

- **Calling `NEVPNManager.shared().connection.status` for VPN detection.** It only sees the calling app's own VPN configurations. CellGuard owns no VPN config. Will always return `.invalid` or `.disconnected` for third-party tunnels regardless of actual VPN state. [VERIFIED: kean.blog]
- **Polling `getifaddrs()` for `utun*` interface names.** Apple system services use `utun0` / `utun1` / `utun2` even when no user VPN is up. False positives. [VERIFIED: Apple Developer Forums thread/671678]
- **Using `path.usesInterfaceType(.other) == true` as the sole VPN signal.** `.other` fires for various non-VPN scenarios (some tethering setups, system loopback). Use it only as corroborating evidence (D-07 already does this correctly).
- **Calling `loadFromPreferences()` in CellGuard's startup.** Pointless because CellGuard owns no VPN config; will not populate any third-party state.
- **Subscribing to `NEVPNStatusDidChangeNotification`.** Same reasoning: only the calling app's own connection posts this notification. Will never fire for third-party VPNs.
- **Holding the proxy-settings dictionary across long async waits.** `CFNetworkCopySystemProxySettings()` returns a snapshot. Re-call at every capture site rather than caching.
- **Adding a `.vpn` case to `InterfaceType`.** D-04 explicitly forbids this — would cause SwiftData enum migration headache and lose the ground-truth value of `interfaceType`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VPN tunnel detection | Custom `getifaddrs()` enumeration with utun-prefix matching | `CFNetworkCopySystemProxySettings()` | The `__SCOPED__` dictionary already filters to interfaces with active routing/proxy rules, eliminating the false-positive Apple-system-service `utun0/1/2` interfaces. Hand-rolled `getifaddrs` cannot make this distinction. |
| 6-state enum (Int rawValue + encodingString + decoder + displayName) | A single source-of-truth dictionary literal | The 4-method pattern in `ConnectivityEvent.swift` lines 281-368 | Established codebase convention. EventType, PathStatus, InterfaceType all use this shape. SwiftData `@Model` does not support enum types directly (per the comment at line 47), so `Int` rawValue storage is mandatory. |
| Privacy gating for VPN field | A new userInfo key | The existing `omitLocation` userInfo flag (D-08) | Single-axis privacy is the user-visible model. Adding a second flag doubles UI complexity for no diagnostic gain. |
| Live VPN binding to dashboard | A KVO observer on NEVPNManager | `@Observable private(set) var currentVPNState` updated in `handlePathUpdate` and `captureVPNState` | Already-paid-for Observation framework infrastructure. Mirrors `currentRadioTechnology` exactly. |
| Reasserting detection | A custom dispatch source watching `ifa_flags` | `vpnReassertingUntil: Date?` flag set on path-drop events | iOS does not expose VPN reassertion as a system signal to non-owning apps. The 5-second window heuristic is the standard fallback. |

**Key insight:** Every VPN-detection technique that does NOT require an entitlement is, fundamentally, *inferring* VPN state rather than directly observing it. Embrace the inference. Don't try to hand-roll a "real" VPN observer because no public iOS API provides one for third-party tunnels — even Tailscale (a major VPN provider on iOS) had to build inference workarounds (per their PR #10680).

## Common Pitfalls

### Pitfall 1: NEVPNManager's app-scoping silently returning .disconnected

**What goes wrong:** Developer wires up `NEVPNManager.shared().connection.status` thinking it observes any VPN; testing on simulator with no Settings VPN profile, status reads `.disconnected` always; developer ships, then user with Mullvad VPN sees the same `.disconnected` value because Mullvad is not CellGuard's app's config.
**Why it happens:** Apple's docs use the singular "the VPN" without making the calling-app-scoping explicit on the API surface. The scoping is buried in the high-level Personal VPN docs.
**How to avoid:** Use `CFNetworkCopySystemProxySettings()` instead. Document the rejection of `NEVPNManager` in code comments above `captureVPNState()`.
**Warning signs:** Status always `.disconnected`/`.invalid` even when `NWPathMonitor` reports `.other` interface and the device's WiFi/Cellular indicator shows the VPN icon.

### Pitfall 2: `.other` interface mistakenly absorbed into "Wi-Fi only" classifications

**What goes wrong:** A probe failure during VPN-over-cellular returns `capturedInterface == .other` (because `detectPrimaryInterface` returns `.other` for `utun*`). Without D-07's `effectivelyCellular` check, the existing line-266 silent-failure branch is bypassed and the event is mis-classified as `.probeFailure`.
**Why it happens:** `NWPath.availableInterfaces` orders the VPN tunnel first when it's up; the underlying transport is the second entry; `detectPrimaryInterface` only inspects `[0]`.
**How to avoid:** D-07's `effectivelyCellular` check fixes this for the silent-failure branch. Implement it exactly as written. Do **not** also change `detectPrimaryInterface` itself — `interfaceType` is meant to be ground truth (D-04).
**Warning signs:** A run with VPN-over-cellular shows zero `.silentFailure` events even when the user reports drops; `.probeFailure` count rises instead.

### Pitfall 3: Reasserting window leaking past the actual reassert

**What goes wrong:** `vpnReassertingUntil` is set to "now + 5s" on every path drop; if the user genuinely loses connectivity for 30s with VPN up, every event in the 5s window after the drop gets labeled `.reasserting` even though the tunnel never came back.
**Why it happens:** The window is set on path drop but doesn't validate that the tunnel actually came back; CFNetworkCopySystemProxySettings can return `true` (tunnel registered) even while the underlying connectivity is not satisfied.
**How to avoid:** Only label `.reasserting` if (a) `vpnReassertingUntil > now` AND (b) detector still returns true AND (c) `currentPathStatus == .satisfied`. The third condition prevents leaking into truly-down events.
**Warning signs:** Multi-minute outages show a brief flurry of "Reconnecting" events at the start, then nothing, instead of a clean disconnect.

### Pitfall 4: SwiftData @Model auto-storage for enum types

**What goes wrong:** Developer adds `var vpnState: VPNState?` directly to the `@Model` class; SwiftData errors at runtime with "Cannot store enum types in @Model" or similar.
**Why it happens:** SwiftData supports `Codable` enum storage in some cases but the project deliberately uses Int rawValue storage with computed accessors because (per the comment at line 46-47 of ConnectivityEvent.swift) **SwiftData does not support enum types in `#Predicate` queries.**
**How to avoid:** Mirror the existing `eventTypeRaw` / `pathStatusRaw` / `interfaceTypeRaw` pattern. Store `vpnStateRaw: Int?`; expose `vpnState: VPNState?` as a computed property reading/writing `vpnStateRaw`.
**Warning signs:** `@Query` predicates that filter on `vpnState` fail to compile or return unexpected results.

### Pitfall 5: NWPath qualification regression

**What goes wrong:** Phase 7 disambiguated `NWPath` to `Network.NWPath` in 3 places to resolve a build error after `import NetworkExtension`. Phase 8 (which doesn't add `import NetworkExtension` to anywhere new) might accidentally introduce an unqualified `NWPath` reference and the build still works (because `Network` and `NetworkExtension` define ambiguous-but-mostly-compatible types, the compiler may pick one), then break later when a project-wide change reorders import resolution.
**Why it happens:** Phase 7's qualification is a "soft" fix that depends on import order; not all `NWPath` references are guarded.
**How to avoid:** Continue using `Network.NWPath` consistently. New code in `runProbe()` and `handlePathUpdate` already operates on the qualified `Network.NWPath` parameter — keep it that way.
**Warning signs:** Build error "ambiguous use of 'NWPath'" after a Phase 8 commit.

### Pitfall 6: Detector polling cadence vs. path-update cadence

**What goes wrong:** `captureVPNState()` is called only at `logEvent()` time. Between events (especially during long quiet periods on cellular with no path changes), the dashboard's `currentVPNState` goes stale; user toggles VPN on, dashboard label doesn't flip until the next probe (60s away).
**Why it happens:** The detector is only invoked when an event is being logged, not on a schedule.
**How to avoid:** Also invoke `captureVPNState()` in `handlePathUpdate()` whenever a path callback fires (path callbacks DO fire when a VPN comes up — the new utun interface causes a path change). Combined with the existing 500ms debounce, this gives sub-second VPN-up dashboard updates.
**Warning signs:** Dashboard label shows "Other" for ~60s after the user enables VPN, then flips to "VPN" only when the next probe runs.

### Pitfall 7: CFNetworkCopySystemProxySettings background restriction

**What goes wrong:** The function is called during a background wake (significant location change) and returns nil or empty `__SCOPED__` because the app context is restricted.
**Why it happens:** Some `SystemConfiguration` queries are throttled or stubbed in background extension contexts.
**How to avoid:** Treat nil/empty as "VPN state unknown, fall back to previous detector state." Already aligned with the inference logic — `previousVPNDetectorState` carries forward across the gap. This phase does not need any new code path; the design already degrades gracefully.
**Warning signs:** Background-wake events sporadically lose VPN state (vpnState appears nil even when previous and next events have it).

## Code Examples

### Example 1: VPNState enum following the established pattern

```swift
// Source: pattern matches ConnectivityEvent.swift InterfaceType (lines 31-38, 328-353)

enum VPNState: Int, Codable, CaseIterable {
    case invalid = 0
    case disconnected = 1
    case connecting = 2
    case connected = 3
    case reasserting = 4
    case disconnecting = 5
}

extension VPNState {
    /// Stable camelCase identifier for JSON export (matches NEVPNStatus enum names lowercased).
    var encodingString: String {
        switch self {
        case .invalid: "invalid"
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .reasserting: "reasserting"
        case .disconnecting: "disconnecting"
        }
    }

    /// Decodes from a stable encoding string. Returns nil if unrecognized.
    static func fromEncodingString(_ string: String) -> VPNState? {
        switch string {
        case "invalid": .invalid
        case "disconnected": .disconnected
        case "connecting": .connecting
        case "connected": .connected
        case "reasserting": .reasserting
        case "disconnecting": .disconnecting
        default: nil
        }
    }
}

extension VPNState {
    /// Human-readable name for UI display (UI-SPEC State Display Projection table).
    /// Note: `.reasserting` displays as "Reconnecting" — internal API jargon translated to user-friendly term.
    var displayName: String {
        switch self {
        case .invalid: "Invalid"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reasserting: "Reconnecting"
        case .disconnecting: "Disconnecting"
        }
    }
}
```

### Example 2: VPN active detector

```swift
// Source: medium/nishant.taneja, Apple Developer Forums thread/113491
// Verified pattern across 4 independent sources.

import SystemConfiguration

private func isVPNActive() -> Bool {
    guard let cfDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
          let scoped = cfDict["__SCOPED__"] as? [String: Any] else {
        return false
    }
    let prefixes = ["utun", "ipsec", "tap", "tun", "ppp"]
    for key in scoped.keys {
        let lowered = key.lowercased()
        if prefixes.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
    }
    return false
}
```

### Example 3: 6-state inference function

```swift
// Source: original — synthesizes the 6-state CONTEXT.md model from the 2-state detector.
// Lives on @MainActor ConnectivityMonitor alongside captureRadioTechnology() etc.

@MainActor
private func captureVPNState() -> VPNState {
    let detectorNow = isVPNActive()
    let detectorPrev = previousVPNDetectorState
    defer { previousVPNDetectorState = detectorNow }

    // Reasserting takes precedence: if we're inside a "reassert window" and tunnel still up
    if let until = vpnReassertingUntil,
       Date() < until,
       detectorNow,
       currentPathStatus == .satisfied {
        return .reasserting
    }

    switch (detectorPrev, detectorNow) {
    case (false, true):  return .connecting
    case (true, true):   return .connected
    case (true, false):  return .disconnecting
    case (false, false): return .disconnected
    }
}
```

### Example 4: Effective interface label (computed)

```swift
// Lives on @Observable ConnectivityMonitor, parallel to currentInterfaceType.

var effectiveInterfaceLabel: String {
    switch currentVPNState {
    case .connected, .reasserting: return "VPN"
    default: return currentInterfaceType.displayName
    }
}
```

### Example 5: Per-event display helper (for EventDetailView's Section "VPN" condition)

```swift
// On ConnectivityEvent extension; used by EventDetailView to gate Section visibility.
// UI-SPEC locks: section visible when state ∉ {disconnected, invalid}.

extension ConnectivityEvent {
    var shouldShowVPNSection: Bool {
        guard let state = vpnState else { return false }
        return state != .disconnected && state != .invalid
    }
}
```

### Example 6: Encode block update for privacy-gated VPN export

```swift
// In ConnectivityEvent.encode(to:), inside the existing `if !omitLocation` block.
// UI-SPEC export contract: omit .disconnected and .invalid from JSON for compactness.

let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)
    // NEW: VPN state, with state-value filter
    if let state = vpnState, state != .disconnected, state != .invalid {
        try container.encode(state.encodingString, forKey: .vpnState)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NEVPNManager.shared().connection.status` for any VPN detection | App-scoped only — use `CFNetworkCopySystemProxySettings()` for third-party detection | iOS 8 (when NEVPNManager shipped — never claimed third-party scope, but commonly mis-applied) | Major — most "Swift VPN detection" tutorials older than 2019 still recommend NEVPNManager incorrectly |
| `CTCarrier` for carrier name | Returns nil on iOS 16.4+ — accept "Unknown" | iOS 16.4 | Already handled in CellGuard (Phase 2 research). Carrier shows as nil in events. |
| `CNCopyCurrentNetworkInfo` for SSID | `NEHotspotNetwork.fetchCurrent()` | iOS 14 | Already handled in Phase 7. |
| `Combine` `@Published` for monitor state | `@Observable` via Observation framework | iOS 17 | Already used by ConnectivityMonitor. New `currentVPNState` follows the same pattern. |
| Manual `VersionedSchema` for additive optional fields | Lightweight migration auto-handled | SwiftData iOS 17 onward | No migration plan needed for Phase 8. |

**Deprecated/outdated:**
- `NEVPNManager` for third-party detection: never the right tool, but commonly cited in older tutorials.
- `getifaddrs()` raw-prefix matching: ambiguous with Apple system services (utun0-2).
- `SCDynamicStore` (`scutil --nc list`): Apple staff (forums/671678) note this misses third-party VPNs like TunnelBlick, Viscosity. CFNetworkCopySystemProxySettings is the more inclusive signal.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `CFNetworkCopySystemProxySettings()` returns the `__SCOPED__` dictionary even in background-wake contexts (significant location change) | Pitfall 7 | Medium — VPN state shows nil for ~half of events. Mitigation: `previousVPNDetectorState` carries forward; events still get prior steady-state value. Need to test on the iPhone 17 Pro Max once during a sig-loc-wake. |
| A2 | The 5-second `vpnReassertingUntil` window covers typical Wi-Fi→cellular handover for WireGuard/IPSec on iOS 26 | Detection Mechanism > .reasserting detection | Medium — if real reassertion takes 8-10s, those events are misclassified as `.disconnected` not `.reasserting`. Adjustable constant; tune based on real-device observation. |
| A3 | `NWPath.usesInterfaceType(.cellular)` returns true when a VPN is up over cellular (i.e., the underlying transport is reflected in the path even though primary interface is `.other`) | VPN-04 Decision Tree (D-07 implementation) | HIGH — this is the entire premise of D-07. If `usesInterfaceType(.cellular)` returns false for VPN-over-cellular, D-07's `effectivelyCellular` check never fires for the VPN case and the silent-failure-during-VPN gap remains. **Recommendation: verify on real iPhone 17 Pro Max with Mullvad enabled before plan approval** — this is testable in a 10-minute manual experiment. |
| A4 | iOS 26 has not deprecated or restricted `CFNetworkCopySystemProxySettings()` for third-party apps | Standard Stack | LOW — function has been stable since iOS 2.0; iOS 26 release notes (cross-checked against Microsoft Learn iOS entitlements doc) do not mention SystemConfiguration deprecations. |
| A5 | Apple's own VPN-related `utun` interfaces (CarPlay, Continuity, etc.) do NOT register `__SCOPED__` keys, only user-visible VPN tunnels do | Detection Mechanism | MEDIUM — if Apple's iCloud Private Relay (introduced iOS 15) registers a `__SCOPED__` entry, every iCloud-Plus user would show "VPN active" continuously. Recommend verifying on the iPhone 17 Pro Max with iCloud+ enabled. If Private Relay is detected: extend prefix matching to exclude known Apple utun ranges, or accept that "Private Relay = VPN" for the purposes of CellGuard's analysis (defensible — Private Relay is a tunnel; the user did opt into it). |
| A6 | The new `vpnStateRaw: Int?` field requires no SwiftData VersionedSchema | Schema Migration | LOW — Phase 7's `wifiSSID` shipped this way and works. |

**Recommendation:** A3 should be verified before plan-phase (10-minute manual test). A1, A2, A5 are testable during phase implementation (Wave 0 / first task). A4 and A6 are low-risk and can be assumed.

## Open Questions (RESOLVED)

1. **D-06 strict (connecting/reasserting only) vs. broader (any VPN up + cellular path)?**
   - What we know: CONTEXT.md D-06 explicitly says "vpnState ∈ {connecting, reasserting}." VPN-04 acceptance text says "Wi-Fi loss while VPN is reconnecting" — narrower wording matches D-06.
   - What's unclear: whether the user wants the **broader** interpretation (any VPN-up + cellular-effective + probe-fail = silent failure, a clean MON-03 extension), or the **narrower** D-06 trigger (only the handover moment).
   - Recommendation: **planner asks the user during plan review** before implementing the catch branch. Both are 5-line changes; the choice affects how much silent-failure signal is captured. My recommendation as researcher is the broader interpretation: it's the cleaner extension of MON-03 and matches the spirit of "the silent-failure branch is the entire reason this app exists" (D-07 rationale).
   - **RESOLVED:** User chose BROAD trigger during /gsd-plan-phase 8 (2026-04-25). D-06's narrow `vpnState ∈ {connecting, reasserting}` is superseded by the BROAD-trigger override implemented in Plan 03 step J: reclassify as `.silentFailure` whenever (probe failed) AND (path satisfied) AND (effectively cellular), regardless of which non-trivial VPN substate is active. Audit trail preserved in CONTEXT.md, DISCUSSION-LOG.md Q5, and PATTERNS.md.

2. **iCloud Private Relay false positive (A5)?**
   - What we know: iCloud Private Relay creates QUIC tunnels that may register in `__SCOPED__`.
   - What's unclear: whether they appear with `utun*` keys or with non-tunneling-prefix keys.
   - Recommendation: 5-minute test on the iPhone 17 Pro Max with Private Relay toggled on/off. If it triggers detection: document as expected behavior (Private Relay IS a tunnel) or add an exclude list of known-Apple identifiers.
   - **RESOLVED:** Deferred to Plan 01 Wave 0 Check 3 — verify on iPhone 17 Pro Max during phase implementation. Disposition (accept-as-tunnel vs. exclude-list) is a small UX call to be made when test data lands; does not block plan execution.

3. **Should VPN-04 also fire `.silentFailure` when probe fails on `.wifi` interface AND VPN is `.reasserting`?**
   - What we know: D-07 only treats `.other` as cellular under VPN. Wi-Fi probe failures stay as probe failure.
   - What's unclear: a Wi-Fi-loss-mid-reassert scenario where the path momentarily reports Wi-Fi (briefly satisfied via Wi-Fi before the tunnel reasserts on cellular) followed by a probe failure. Strict reading: classify as probe-failure. User intent: probably silent-failure (VPN-04 is about the handover moment). Edge case; flag for plan review.
   - **RESOLVED:** Deferred post-deployment. Strict reading (probe-failure on `.wifi`) is implemented; revisit only if real-device data shows the misclassification materially. Edge case is rare enough that adding code now would be premature.

4. **Does `NWPathMonitor` fire a path-update callback when a third-party VPN comes up/goes down?**
   - What we know: the new `utun*` interface joining `availableInterfaces` should trigger an update.
   - What's unclear: whether iOS 26 batches/suppresses these for non-owning apps.
   - Recommendation: verify during Wave 0; if NOT — fall back to also calling `captureVPNState()` from the probe timer (60s cadence is the worst case for VPN-up label latency).
   - **RESOLVED:** Deferred to Plan 01 Wave 0 Check 4 — verify behavior on iPhone 17 Pro Max with Mullvad toggle. If callback does not fire reliably, fall back to per-probe `captureVPNState()` (worst-case 60s label latency, acceptable for diagnostic use case).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SystemConfiguration.framework | VPN detection (`CFNetworkCopySystemProxySettings`) | ✓ | iOS 2.0+ (auto-linked) | — |
| Network.framework | NWPath inspection | ✓ | iOS 12+ (already imported) | — |
| NetworkExtension.framework | Reference only (not used for VPN detection in Phase 8) | ✓ | iOS 8+ (already imported) | — |
| SwiftData | Storage | ✓ | iOS 17+ (already in use) | — |
| Xcode 26 / Swift 6.2 / iOS 26 SDK | Build target | ✓ | per CLAUDE.md | — |
| iPhone 17 Pro Max with iOS 26 | Manual testing | Assumed yes | — | None — required for A3 / Pitfall 7 verification |
| Mullvad or WireGuard or system VPN profile installed on test device | Manual VPN-state verification | User's call | — | If unavailable: use the iOS Settings VPN profile (free) for IKEv2 manual config; or test in Xcode simulator with a configured VPN profile (limited fidelity) |

**No code- or build-system-blocking missing dependencies.**

## Validation Architecture

> CellGuard's `.planning/config.json` does not currently set `workflow.nyquist_validation`. Default = enabled. Including this section.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None — no test target exists in the project |
| Config file | none |
| Quick run command | `xcodebuild build -scheme CellGuard -destination 'generic/platform=iOS'` |
| Full suite command | manual UAT per HUMAN-UAT.md (Phase 7 precedent) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VPN-01 | vpnState recorded on every event | Manual UAT | none — visual inspection of EventDetailView "VPN" section + JSON export | ❌ Wave 0 (HUMAN-UAT.md update) |
| VPN-02 | "VPN" label on dashboard when tunnel up | Manual UAT | none — toggle Mullvad on, observe dashboard within 5s | ❌ Wave 0 (HUMAN-UAT.md update) |
| VPN-03 | VPN state in JSON privacy-off, omitted privacy-on | Manual UAT | none — export both states, diff JSON | ❌ Wave 0 (HUMAN-UAT.md update) |
| VPN-04 | Silent failure during VPN reconnect | Manual UAT | none — toggle Wi-Fi off while VPN-over-Wi-Fi, observe event log | ❌ Wave 0 (HUMAN-UAT.md update) |

### Sampling Rate
- **Per task commit:** `xcodebuild build -scheme CellGuard -destination 'generic/platform=iOS'` (build only — no unit tests in project)
- **Per wave merge:** Manual smoke test on iPhone 17 Pro Max — 4 acceptance criteria
- **Phase gate:** HUMAN-UAT.md walkthrough before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `08-HUMAN-UAT.md` — VPN-01 / VPN-02 / VPN-03 / VPN-04 acceptance walkthroughs
- [ ] No new test infrastructure needed — match Phase 6/7 pattern (manual UAT only)
- [ ] No new framework install needed

*Note: CellGuard has no XCTest target. This matches the project's "personal diagnostic tool" scope (CLAUDE.md). Adding a test target is a deferred decision (project-level); not in scope for Phase 8.*

## Sources

### Primary (HIGH confidence)
- Context7 / `/websites/developer_apple_networkextension` — NEVPNStatus enum cases, NEVPNManager.shared() scoping, NEVPNStatusDidChange notification, loadFromPreferences contract, Personal VPN entitlement requirements
- [Apple Developer — NEVPNStatus](https://developer.apple.com/documentation/networkextension/nevpnstatus) — 6 states with availability iOS 8.0+
- [Apple Developer — NEVPNManager](https://developer.apple.com/documentation/networkextension/nevpnmanager) — class scoping, entitlement requirements, shared() singleton
- [Apple Developer — NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) — interface enumeration, path callback semantics
- [Apple Developer Forums #113491 (Quinn "The Eskimo!")](https://developer.apple.com/forums/thread/113491) — official guidance: no public API for active VPN detection; CFNetwork workaround code
- [Apple Developer Forums #671678 (Matt Eaton, Apple DTS)](https://developer.apple.com/forums/thread/671678) — utun* interfaces include Apple system services; SCDynamicStore/scutil limitations
- [WWDC 2023 Session 10195 — Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) — additive-optional auto-migration

### Secondary (MEDIUM confidence)
- [kean.blog — VPN, Part 1: VPN Profiles](https://kean.blog/post/vpn-configuration-manager) — definitive third-party explanation of NEVPNManager calling-app-scoping
- [Tarka Labs — VPN detection guide for iOS and Android](https://tarkalabs.com/blogs/vpn-detection-guide-ios-android/) — proxy-settings approach
- [medium/nishant.taneja — VPN Network Detection in iOS](https://medium.com/@nishant.taneja/vpn-network-detection-in-ios-technical-foundations-implementation-and-best-practices-c1408df2f392) — exact CFNetworkCopySystemProxySettings code
- [medium/swornimshah — VPN Detection for iOS apps](https://medium.com/@swornimshah29/vpn-detection-for-ios-apps-1cb51a7c0941) — interface-prefix list confirmation
- [medium/itsuki — Get Network Information & Monitor Changes](https://medium.com/@itsuki.enjoy/little-swiftui-tip-get-network-information-monitor-changes-aac6e23a0f22) — NWInterface.name accessibility
- [Tailscale PR #10680 — handle iOS network transitions when exit node in use](https://github.com/tailscale/tailscale/pull/10680) — production-grade VPN provider's NWPathMonitor workarounds
- [DEV — WWDC 2025 SwiftData iOS 26 Class Inheritance & Migration](https://dev.to/arshtechpro/wwdc-2025-swiftdata-ios-26-class-inheritance-migration-issues-30bh) — iOS 26 SwiftData migration confirmations
- [Atomic Robot — An Unauthorized Guide to SwiftData Migrations](https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/) — additive-optional safety
- [Apple Developer Forums #748049 — SwiftData Migration Plan](https://developer.apple.com/forums/thread/748049) — caution against unnecessary explicit migration plans

### Tertiary (LOW confidence — not used for load-bearing decisions)
- [medium/alessandrofrancucci — Checking VPN Connection on iOS Swift](https://medium.com/@alessandrofrancucci/checking-vpn-connection-on-ios-swift-9748d733e49d) — confirms CFNetwork approach but code not retrievable
- [Microsoft Learn — iOS entitlements (.NET MAUI)](https://learn.microsoft.com/en-us/dotnet/maui/ios/entitlements?view=net-maui-10.0) — confirms `com.apple.developer.networking.vpn.api` is the Personal VPN entitlement key

### Codebase scan (HIGH confidence, primary)
- `CellGuard/Models/ConnectivityEvent.swift` — enum patterns, Codable conformance, omitLocation gate
- `CellGuard/Services/ConnectivityMonitor.swift` — captureWifiSSID async pattern, runProbe race-safety, processPathChange edge transitions
- `CellGuard/Views/EventDetailView.swift` — conditional Section pattern
- `CellGuard/Views/DashboardView.swift` — interface label binding (line 180), privacy toggle (line 97)
- `CellGuard/Models/EventLogExport.swift` — encoder.userInfo[.omitLocation] flag setting
- `.planning/phases/07-wifi-context/07-RESEARCH.md` — async capture in Task block, Network.NWPath disambiguation
- `.planning/phases/07-wifi-context/07-PATTERNS.md` — file-by-file integration template

## Metadata

**Confidence breakdown:**
- Standard stack & detection mechanism: HIGH — 4+ independent sources confirm CFNetworkCopySystemProxySettings is the public-API path; Apple Developer Forums (Quinn) explicitly states no better public API exists.
- 6-state inference rules: MEDIUM — straightforward state machine, but `.reasserting` window heuristic is empirical and needs A2 verification on real device.
- VPN-04 decision tree: HIGH on the structure, MEDIUM on D-06 narrow vs broad interpretation (Open Question 1).
- Schema migration: HIGH — Phase 7 empirically verified for an analogous additive-optional field.
- File-level integration: HIGH — every change site traces to an existing analog in the codebase.
- D-07 `effectivelyCellular` correctness: contingent on A3 (`path.usesInterfaceType(.cellular)` returning true under VPN-over-cellular) — **needs 10-minute device test before plan approval**.
- Free-team viability: HIGH — no entitlements involved; SystemConfiguration is auto-linked.

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (30 days; iOS 26 is a stable target, no fast-moving framework dependencies)
