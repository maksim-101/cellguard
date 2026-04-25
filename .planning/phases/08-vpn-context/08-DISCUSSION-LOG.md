# Phase 8: VPN Context - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-25
**Phase:** 08-vpn-context
**Areas discussed:** VPN state representation, UI labeling, VPN-handover silent failure

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| VPN detection mechanism | NEVPNManager vs NWPath interfaces vs hybrid — what we can reliably detect, esp. 3rd-party VPNs | |
| VPN state representation | Clean 3-state vs full 6-state NEVPNStatus vs binary on/off | ✓ |
| UI labeling of "VPN" | Computed display override vs new InterfaceType.vpn case vs separate VPN section | ✓ |
| VPN-handover silent failure | Conditions under which VPN-handover probe failures reclassify as silentFailure | ✓ |

**User's choice:** VPN state representation, UI labeling of "VPN", VPN-handover silent failure (detection mechanism deferred to research).

---

## VPN State Representation

### Q1: Which VPN state model should we record on every event?

| Option | Description | Selected |
|--------|-------------|----------|
| 3-state spec (Recommended) | connected / disconnected / connecting per VPN-01 — clean, simple, easy export | |
| Full 6-state NEVPNStatus | invalid / disconnected / connecting / connected / reasserting / disconnecting | ✓ |
| Binary on/off | isVPNActive: Bool — loses 'connecting' state | |

**User's choice:** Full 6-state NEVPNStatus.
**Notes:** Captured the rich enum at the model level for diagnostic value (especially `reasserting` for VPN-04). UI projects this down to the spec's 3 states.

### Q2: Should we capture the VPN tunnel name (e.g. 'Mullvad WireGuard') alongside the state?

| Option | Description | Selected |
|--------|-------------|----------|
| State only (Recommended) | Match VPN-01 spec literally — one new field, less surface area | ✓ |
| State + tunnel name | Capture localizedDescription too — more forensic value, second privacy-gated field | |

**User's choice:** State only.

---

## UI Labeling of "VPN"

### Q3: How should the UI show that a VPN tunnel is active?

| Option | Description | Selected |
|--------|-------------|----------|
| Computed display override (Recommended) | Keep interfaceType raw, add computed effectiveInterfaceLabel returning "VPN" when VPN connected | ✓ |
| New InterfaceType.vpn case | Add .vpn = 6 to enum and detect in detectPrimaryInterface — schema/migration impact | |
| Separate VPN section in EventDetail | Leave "Interface: Other" — doesn't satisfy VPN-02 | |

**User's choice:** Computed display override.
**Notes:** Lowest-blast-radius option. Preserves the SwiftData schema and the `interfaceType` field as a faithful record of NWPath's report.

### Q4: Where in EventDetailView should VPN state appear?

| Option | Description | Selected |
|--------|-------------|----------|
| New VPN section (Recommended) | Mirror Phase 7 Wi-Fi pattern — conditional Section("VPN") | ✓ |
| Inside existing Network section | LabeledContent row in Section("Network") — tighter, breaks Phase 7 tunnel-section pattern | |

**User's choice:** New VPN section.

---

## VPN-Handover Silent Failure

### Q5: When should a probe failure during a VPN handover be reclassified as silentFailure (VPN-04)?

| Option | Description | Selected |
|--------|-------------|----------|
| VPN connecting + cellular path (Recommended) | vpnState ∈ {connecting, reasserting} AND capturedInterface == .cellular | ✓ |
| VPN connecting on any path | Reclassify whenever VPN is connecting — risks conflating tunnel-down with modem-down | |
| VPN connecting + recent Wi-Fi loss | Adds previousInterfaceType == .wifi within last N seconds — most literal but adds time-window state | |

**User's choice:** VPN connecting + cellular path.

### Q6: How should the existing 'capturedInterface == .cellular' silent-failure check interact with VPN tunnels?

| Option | Description | Selected |
|--------|-------------|----------|
| Treat .other-with-VPN-over-cellular as cellular (Recommended) | Use path.usesInterfaceType(.cellular) when primary is .other and VPN is up | ✓ |
| Keep current logic | Strict capturedInterface == .cellular — VPN-up users miss silent-failure detection entirely | |

**User's choice:** Treat .other-with-VPN-over-cellular as cellular.
**Notes:** Closes a latent gap — without this, the entire silent-failure branch (the reason this app exists) is bypassed whenever any VPN tunnel is active.

---

## Claude's Discretion

- Detection mechanism (NEVPNManager vs NWPath heuristics vs hybrid) — deferred to researcher.
- Privacy toggle copy update — left to planner.
- Whether to expose `currentVPNState` as `@Observable` for live dashboard binding — planner decides based on whether dashboard surfaces a live VPN indicator.

## Deferred Ideas

- Live VPN indicator on the dashboard (Phase 9 candidate)
- Per-tunnel name capture (future quick task if multi-VPN distinction needed)
- MapKit visualization of drops vs VPN state (Future Requirement, separate phase)
- 3rd-party VPN compatibility matrix (researcher output, not a new phase)
