# Requirements — Milestone v1.3 Polish & Analytics

**Started:** 2026-04-25
**Goal:** Sharpen the dashboard and reports so the evidence handed to Apple is unambiguous — fix UI lag, capture VPN context, correct misleading metrics, and surface the patterns hidden in 14 location areas.

---

## Active Requirements

### Chart Polish (CHART)

- [ ] **CHART-01**: User can see a legend on the timeline chart that distinguishes silent failures from overt path-change drops
- [ ] **CHART-02**: User can toggle overt path-change drops off in the timeline chart so silent failures stand out
- [ ] **CHART-03**: User sees the home-screen drop count and chart update within 1 second of a silent failure being detected (no manual refresh)

### VPN Context (VPN)

- [ ] **VPN-01**: Every connectivity event records VPN connection state (connected / disconnected / connecting) alongside the existing Wi-Fi SSID
- [ ] **VPN-02**: User sees "VPN" as the interface label in the UI when a VPN tunnel is active (instead of "Other")
- [ ] **VPN-03**: VPN state is included in JSON export, gated by the same privacy toggle that controls SSID and location
- [ ] **VPN-04**: Probe failures that occur while a VPN tunnel is connecting after Wi-Fi loss are classified as silent modem failures (not as a separate "probe failure" category)

### Polish Leftovers (POLISH)

- [ ] **POLISH-01**: HealthDetailSheet "Last Background Wake" updates live while the sheet is open (not just on first appearance)
- [ ] **POLISH-02**: Duplicate probes within the same minute (timer + app-resume firing close together) are deduplicated so the event log doesn't double-count

### Summary Report (REPORT)

- [ ] **REPORT-01**: "Days monitored" counts distinct calendar days that have ≥1 logged event (correctly excluding cert-expiry gaps and any other monitoring outages)
- [ ] **REPORT-02**: The drop ratio uses cellular-only events as the denominator (drops / cellular events), not total events

### Drop Analytics (ANALYTICS)

- [ ] **ANALYTICS-01**: User sees a heatmap with locations on one axis and a switchable second axis (radio tech / connection type / hour of day)
- [ ] **ANALYTICS-02**: User sees a ranked table of drops per location (location label or coordinates → drop count, descending)

---

## Future Requirements (deferred)

- Map view of drop locations (MapKit pins, colored by silent vs overt) — could complement ANALYTICS-02 but adds a MapKit surface area; revisit if the ranked table is insufficient
- Automatic Feedback Assistant draft / report generation
- watchOS companion app for at-a-glance status

---

## Out of Scope

- Cloud backend or server-side analytics — project is local-only by design
- Drop recovery automation (e.g. programmatic Airplane Mode toggle) — not accessible to third-party apps
- Signal strength (dBm/RSSI) capture — not exposed by iOS to third-party apps
- App Store distribution — personal diagnostic tool deployed via Xcode

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| VPN-01 | Phase 8 — VPN Context | Pending |
| VPN-02 | Phase 8 — VPN Context | Pending |
| VPN-03 | Phase 8 — VPN Context | Pending |
| VPN-04 | Phase 8 — VPN Context | Pending |
| CHART-01 | Phase 9 — Dashboard Polish | Pending |
| CHART-02 | Phase 9 — Dashboard Polish | Pending |
| CHART-03 | Phase 9 — Dashboard Polish | Pending |
| POLISH-01 | Phase 9 — Dashboard Polish | Pending |
| POLISH-02 | Phase 9 — Dashboard Polish | Pending |
| REPORT-01 | Phase 10 — Reports & Analytics | Pending |
| REPORT-02 | Phase 10 — Reports & Analytics | Pending |
| ANALYTICS-01 | Phase 10 — Reports & Analytics | Pending |
| ANALYTICS-02 | Phase 10 — Reports & Analytics | Pending |

**Coverage:** 13/13 ✓ — all v1.3 requirements mapped to a phase, no orphans, no duplicates.
