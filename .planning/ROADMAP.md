# Roadmap: CellGuard

## Milestones

- ✅ **v1.0 MVP** — Phases 1-4 (shipped 2026-03-25) — [Archive](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 Privacy Export** — Phase 5 (shipped 2026-03-26) — [Archive](milestones/v1.1-ROADMAP.md)
- ✅ **v1.2 Persistent Signing & Wi-Fi Context** — Phases 6-7 (shipped 2026-04-21) — [Archive](milestones/v1.2-ROADMAP.md)
- 🚧 **v1.3 Polish & Analytics** — Phases 8-10 (started 2026-04-25)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-4) — SHIPPED 2026-03-25</summary>

- [x] Phase 1: Foundation (1/1 plans) — SwiftData schema, EventStore, app shell
- [x] Phase 2: Core Monitoring (2/2 plans) — NWPathMonitor, HEAD probe, silent failure detection
- [x] Phase 3: Background Lifecycle (3/3 plans) — 24h+ background execution, gap tracking, health indicators
- [x] Phase 4: UI and Evidence Export (3/3 plans) — Dashboard, charts, notifications, JSON export

</details>

<details>
<summary>✅ v1.1 Privacy Export (Phase 5) — SHIPPED 2026-03-26</summary>

- [x] Phase 5: Privacy-Aware Export (1/1 plans) — Privacy toggle, location stripping, metadata envelope

</details>

<details>
<summary>✅ v1.2 Persistent Signing & Wi-Fi Context (Phases 6-7) — SHIPPED 2026-04-21</summary>

- [x] Phase 6: Persistent Signing (1/1 plans) — Paid team signing, certificate expiry monitoring
- [x] Phase 6.1: Signing Polish (1/1 plans) — Profile reading fix, Xcode warning cleanup
- [x] Phase 7: Wi-Fi Context (1/1 plans) — SSID capture, event detail display, privacy-gated export

</details>

### v1.3 Polish & Analytics (Phases 8-10) — IN PROGRESS

- [ ] **Phase 8: VPN Context** — Capture, display, export, and reclassify connectivity events with VPN state
- [ ] **Phase 9: Dashboard Polish** — Live-updating dashboard with probe dedup, silent-failure legend, and overt-drop filter
- [ ] **Phase 10: Reports & Analytics** — Corrected Summary Report metrics and per-location drop analytics

## Phase Details

### Phase 8: VPN Context
**Goal**: Every connectivity event captures VPN tunnel state, the UI labels VPN tunnels accurately, the privacy-gated export carries VPN state, and probe failures during VPN handover are correctly attributed to silent modem failures.
**Depends on**: Phase 7 (extends the existing event pipeline established in Phases 1–7)
**Requirements**: VPN-01, VPN-02, VPN-03, VPN-04
**Success Criteria** (what must be TRUE):
  1. User opens any event in the event log and sees a VPN field showing connected / disconnected / connecting state
  2. User connecting to a VPN tunnel sees the dashboard interface label change from "Other" to "VPN"
  3. User exports JSON with privacy toggle OFF and finds VPN state in each event; with privacy toggle ON, VPN state is omitted alongside SSID and location
  4. User loses Wi-Fi while a VPN is reconnecting and the resulting probe failure is logged as a silent modem failure (not a separate "probe failure" category)
**Plans**: 4 plans
Plans:
- [ ] 08-01-PLAN.md — Wave 0: device-test verification of CFNetworkCopySystemProxySettings + path.usesInterfaceType(.cellular) + iCloud Private Relay false-positive guard + NWPath callback firing on VPN transitions
- [ ] 08-02-PLAN.md — Add VPNState enum, vpnStateRaw storage, init param, CodingKey, decoder, and privacy-gated encoder to ConnectivityEvent.swift
- [ ] 08-03-PLAN.md — Add CFNetworkCopySystemProxySettings detection, live currentVPNState binding, captureVPNState capture, BROAD VPN-04 silent-failure reclassification, and effectiveInterfaceLabel to ConnectivityMonitor.swift
- [ ] 08-04-PLAN.md — Add Section("VPN") + VPNState.displayName to EventDetailView; flip dashboard interface label to effectiveInterfaceLabel; update privacy toggle copy to mention VPN

### Phase 9: Dashboard Polish
**Goal**: The home screen and HealthDetailSheet stay in sync with reality in real time, the timeline chart distinguishes silent vs overt drops with a legend and an overt-drop filter, and duplicate probes within the same minute no longer pollute the event log.
**Depends on**: Phase 8 (so VPN-tagged events flow through the dashboard reactively without pipeline rework mid-phase)
**Requirements**: CHART-01, CHART-02, CHART-03, POLISH-01, POLISH-02
**Success Criteria** (what must be TRUE):
  1. User sees a legend on the timeline chart that visually distinguishes silent failures from overt path-change drops
  2. User toggles overt drops off in the chart and only silent failures remain visible
  3. User triggers a silent failure (or one occurs) and the home-screen drop count and chart update within 1 second without manual refresh
  4. User opens HealthDetailSheet and watches "Last Background Wake" tick forward live while the sheet stays open
  5. User reviews the event log and finds no two probe entries in the same minute (timer + app-resume probes within 60s collapse to one)
**Plans**: TBD
**UI hint**: yes

### Phase 10: Reports & Analytics
**Goal**: The Summary Report's headline numbers (days monitored, drop ratio) reflect reality, and the user can mine 14 location areas of data via a switchable-axis heatmap and a ranked drops-per-location table.
**Depends on**: Phase 8 (analytics views can filter/group by VPN where useful) and Phase 9 (metric corrections share dashboard reactivity model)
**Requirements**: REPORT-01, REPORT-02, ANALYTICS-01, ANALYTICS-02
**Success Criteria** (what must be TRUE):
  1. User reads the Summary Report and "Days Monitored" matches the count of distinct calendar days that actually have ≥1 logged event (cert-expiry gaps and outages excluded)
  2. User reads the drop ratio in the Summary Report and confirms it is computed as drops divided by cellular-only events (not total events)
  3. User opens the analytics view and sees a heatmap with locations on one axis and switches the second axis between radio tech, connection type, and hour of day
  4. User sees a ranked table of drops per location, descending by drop count, with location label or coordinates
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.0 | 1/1 | Complete | 2026-03-25 |
| 2. Core Monitoring | v1.0 | 2/2 | Complete | 2026-03-25 |
| 3. Background Lifecycle | v1.0 | 3/3 | Complete | 2026-03-25 |
| 4. UI and Evidence Export | v1.0 | 3/3 | Complete | 2026-03-25 |
| 5. Privacy-Aware Export | v1.1 | 1/1 | Complete | 2026-03-26 |
| 6. Persistent Signing | v1.2 | 1/1 | Complete | 2026-04-20 |
| 6.1 Signing Polish | v1.2 | 1/1 | Complete | 2026-04-20 |
| 7. Wi-Fi Context | v1.2 | 1/1 | Complete | 2026-04-20 |
| 8. VPN Context | v1.3 | 0/4 | Planned | - |
| 9. Dashboard Polish | v1.3 | 0/? | Not started | - |
| 10. Reports & Analytics | v1.3 | 0/? | Not started | - |

## v1.3 Coverage Map

| Requirement | Phase |
|-------------|-------|
| VPN-01 | Phase 8 |
| VPN-02 | Phase 8 |
| VPN-03 | Phase 8 |
| VPN-04 | Phase 8 |
| CHART-01 | Phase 9 |
| CHART-02 | Phase 9 |
| CHART-03 | Phase 9 |
| POLISH-01 | Phase 9 |
| POLISH-02 | Phase 9 |
| REPORT-01 | Phase 10 |
| REPORT-02 | Phase 10 |
| ANALYTICS-01 | Phase 10 |
| ANALYTICS-02 | Phase 10 |

**Total mapped:** 13/13 v1.3 requirements ✓ — no orphans, no duplicates.
