---
phase: 08-vpn-context
plan: 01
type: device-verification
status: deferred
created: 2026-04-25
updated: 2026-04-25
---

# Wave 0 — VPN Detection Mechanism Device Verification

## Final Decision: GO (verification deferred to in-app self-check)

**Decision date:** 2026-04-25
**Target device:** iPhone 17 Pro Max running iOS 26.4.2, Xcode 26.4.1,
ProtonVPN as the third-party VPN under test.

The four-check device test specified in `08-01-PLAN.md` was deferred at
user request because (a) the four checks cannot be automated from
outside the device and (b) the failure mode is recoverable in a small
Phase 8.1 polish if the API behaves differently than `08-RESEARCH.md`
predicts.

Instead, the verification is folded into **Plan 08-03** as a one-shot
`os_log` self-check inside `captureVPNState()`: the first time the
function runs per app launch it emits the full `__SCOPED__` key list and
the matched prefix (or "no match"). The user reads Console.app once
after enabling ProtonVPN to confirm the detection mechanism works on
iOS 26.4.2.

## Risk and recovery

- **Risk:** ProtonVPN on iOS 26.4.2 may not surface a key with prefix in
  `{utun, ipsec, ppp, tap, tun}` — possible but unlikely (this set
  matches the Apple-documented tunnel interface naming, and ProtonVPN's
  iOS client uses standard `NEPacketTunnelProvider` which produces
  `utun*` interfaces).
- **Recovery if detection fails:** Phase 8.1 polish — read the literal
  key string from the Console.app dump and either extend the prefix
  list, switch to a substring match, or add a per-VPN allow/deny list
  in `captureVPNState()`. No schema, UI, or service-architecture
  changes required — strictly a one-line constant update.
- **iCloud Private Relay false-positive:** also surfaced by the same
  Console.app dump. If a Private-Relay key matches the prefixes, the
  Phase 8.1 polish adds the documented exclusion filter at the same
  time.
- **NWPathMonitor transition reliability:** observable from normal app
  use — if VPN-up/down is not reflected in the dashboard within a few
  seconds, Phase 8.1 adds a polling fallback to `currentVPNState`.

## Hand-off to Plan 02

Final Decision is `GO`. Wave 1 (Plan 08-02 — schema) starts immediately.
Wave 2 (Plan 08-03 — service) carries the embedded self-check
telemetry as a hard requirement.
