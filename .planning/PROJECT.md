# CellGuard

## What This Is

A lightweight iOS diagnostic app that continuously monitors cellular connectivity in the background and logs every detected drop with contextual metadata. Built as a personal tool to produce structured, timestamped evidence for an Apple Feedback Assistant report documenting persistent baseband modem failures on the iPhone 17 Pro Max.

## Core Value

Reliably detect and log every cellular connectivity drop — including the "attached but unreachable" silent modem failure — so there is irrefutable evidence for Apple's engineering team.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Real-time monitoring of network path changes via NWPathMonitor
- [ ] Periodic active connectivity checks (HEAD request to Apple captive portal every 60s) to detect silent modem failures where path reports "satisfied" but no data transits
- [ ] Structured local logging of all connectivity events with full metadata (timestamp, event type, path status, interface type, radio technology, carrier, location, connectivity test result, drop duration)
- [ ] Background execution that persists for 24+ hours without iOS termination or noticeable battery drain
- [ ] CSV/JSON export of the full event log for Feedback Assistant attachment
- [ ] Minimal dashboard UI showing current status, drop count (24h/7d), and scrollable event log
- [ ] Event detail view showing all captured metadata per event
- [ ] Coarse location capture per event for geographic pattern analysis
- [ ] Summary report generation (drops per day, average duration, affected times/locations)

### Out of Scope

- Programmatic drop recovery (toggling Airplane Mode is not accessible to third-party apps)
- Cloud storage, analytics backend, or any external data transmission
- Signal strength (dBm/RSSI) monitoring — Apple does not expose this to third-party apps
- Direct modem/baseband state access — private framework, not available to third-party apps
- App Store distribution — personal diagnostic tool deployed via Xcode
- Wi-Fi SSID capture — requires entitlement not available without paid developer program membership
- OAuth, user accounts, or onboarding flows — single-user tool

## Context

- **Device:** iPhone 17 Pro Max, iOS 26.x, modem firmware 1.55.04, Swisscom 69.0 carrier bundle
- **The bug:** Sporadic cellular connectivity drops persisting across device replacement, multiple iOS versions (26.0–26.4), LTE-only mode, manual carrier selection, network settings reset, and carrier bundle updates. Consistent with documented baseband modem state-machine failure affecting iPhone 17 series, widely reported on MacRumors, Apple forums, and tech press.
- **Recovery:** Only user-side recovery is toggling Airplane Mode (forces baseband re-registration). Not possible during active calls — calls are irrecoverably lost.
- **Sneaky variant:** Device appears registered on network (callers hear ringing, SMS show delivered) but nothing reaches the device. NWPathMonitor may still report "satisfied" in this state.
- **Why not Shortcuts:** No sub-hourly triggers, no persistent background loops, no Airplane Mode toggle, limited network detail exposure.
- **Signing:** Free personal team signing via Xcode — app needs re-deployment every 7 days. Paid Apple Developer Program ($99/yr) is an option later for permanent signing.
- **Tech approach:** NWPathMonitor for real-time path change callbacks + periodic HEAD requests to `apple.com/library/test/success.html` (Apple's captive portal) every 60 seconds to detect silent failures. CTTelephonyNetworkInfo for radio technology and carrier name. Significant location changes (not continuous GPS) for coarse location + background execution eligibility.

## Constraints

- **Platform:** iOS 26.x, SwiftUI, Swift — must target iPhone 17 Pro Max specifically
- **Signing:** Free personal team (7-day re-sign cycle) — no entitlements requiring paid membership
- **Background execution:** Must use legitimate iOS background modes (Background App Refresh, NWPathMonitor background delivery, significant location changes) — no hacks that would cause termination
- **Battery:** Background monitoring must not cause noticeable battery drain
- **Storage:** All data local, no cloud — must handle weeks of event data without significant storage impact
- **Privacy:** No external data transmission whatsoever
- **Development:** Built with Claude Code — standard SwiftUI project structure

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Apple captive portal for connectivity checks | Apple-hosted, always up, lightweight, no privacy concerns, same URL iOS uses internally | — Pending |
| 60-second check interval | Balances drop detection responsiveness with battery impact | — Pending |
| SwiftData or SQLite for local storage | Lightweight, built-in, handles weeks of data | — Pending |
| Significant location changes (not continuous GPS) | Coarse location sufficient for pattern analysis, minimal battery impact, doubles as background execution eligibility | — Pending |
| Free personal team signing | No developer program membership currently — can upgrade later if 7-day cycle becomes burdensome | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-25 after initialization*
