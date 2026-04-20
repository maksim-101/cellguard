# Roadmap: CellGuard

## Milestones

- ✅ **v1.0 MVP** — Phases 1-4 (shipped 2026-03-25) — [Archive](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 Privacy Export** — Phase 5 (shipped 2026-03-26) — [Archive](milestones/v1.1-ROADMAP.md)
- 🚧 **v1.2 Persistent Signing & Wi-Fi Context** — Phases 6-7 (in progress)

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

### 🚧 v1.2 Persistent Signing & Wi-Fi Context (In Progress)

**Milestone Goal:** Switch to paid Apple Developer team signing so the app persists indefinitely, and add Wi-Fi SSID capture for richer environmental context in diagnostic logs.

- [x] **Phase 6: Persistent Signing** - Paid team signing with certificate expiry monitoring replaces 7-day re-sign cycle (completed 2026-04-20)
- [x] **Phase 6.1: Signing Polish** - Fix profile reading on device + resolve all Xcode warnings (completed 2026-04-20)
- [ ] **Phase 7: Wi-Fi Context** - Wi-Fi SSID captured on each event, stored, exported, and displayed

## Phase Details

### Phase 6: Persistent Signing
**Goal**: App persists on device indefinitely with paid team signing, and user is warned before certificate expires
**Depends on**: Phase 5 (completed v1.1 baseline)
**Requirements**: SIGN-01, SIGN-02, EXPR-01, EXPR-02
**Success Criteria** (what must be TRUE):
  1. App is signed with Team ID VTWHBCCP36 and installs on device without free-team limitations
  2. App remains functional on device beyond 7 days without re-deployment
  3. User sees accurate certificate expiry date in the health status UI
  4. User receives a local notification 7 days before certificate expiry
**Plans**: 1 plan
Plans:
- [x] 06-01-PLAN.md — Update ProvisioningProfileService for 7-day warning window and paid-team copy; verify on-device build

### Phase 6.1: Signing Polish
**Goal**: Fix provisioning profile reading on physical device and resolve all Xcode warnings
**Depends on**: Phase 6 (gap closure)
**Requirements**: EXPR-01 (gap closure)
**Success Criteria** (what must be TRUE):
  1. "Cert Expires:" shows a real date on iPhone 17 Pro Max (not "Unknown (Simulator)")
  2. Zero Xcode warnings related to Sendable, deprecated APIs, async access, or missing AccentColor
**Plans**: 1 plan
Plans:
- [x] 06.1-01-PLAN.md — Fix profile reading fallback, resolve Sendable/async/deprecation/AccentColor warnings

### Phase 7: Wi-Fi Context
**Goal**: Every connectivity event captures the current Wi-Fi SSID, providing environmental context for diagnosing cellular drops
**Depends on**: Phase 6 (paid signing enables Access WiFi Information entitlement)
**Requirements**: WIFI-01, WIFI-02, WIFI-03, WIFI-04
**Success Criteria** (what must be TRUE):
  1. When connected to Wi-Fi, the current SSID appears in the event detail view for each logged event
  2. When not connected to Wi-Fi, the SSID field shows nil/empty gracefully (no crash, no placeholder noise)
  3. Exported JSON and CSV files include the Wi-Fi SSID field, respecting the privacy toggle (stripped when enabled)
  4. The SwiftData model stores SSID as a queryable field on ConnectivityEvent
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
| 7. Wi-Fi Context | v1.2 | 0/? | Not started | - |
