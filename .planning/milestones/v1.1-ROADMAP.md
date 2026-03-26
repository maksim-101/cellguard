# Roadmap: CellGuard

## Milestones

- **v1.0 MVP** — Phases 1-4 (shipped 2026-03-25) — [Archive](milestones/v1.0-ROADMAP.md)
- **v1.1 Privacy Export** — Phase 5 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-4) — SHIPPED 2026-03-25</summary>

- [x] Phase 1: Foundation (1/1 plans) — SwiftData schema, EventStore, app shell
- [x] Phase 2: Core Monitoring (2/2 plans) — NWPathMonitor, HEAD probe, silent failure detection
- [x] Phase 3: Background Lifecycle (3/3 plans) — 24h+ background execution, gap tracking, health indicators
- [x] Phase 4: UI and Evidence Export (3/3 plans) — Dashboard, charts, notifications, JSON export

</details>

### v1.1 Privacy Export

- [ ] **Phase 5: Privacy-Aware Export** - Toggle to strip location data from JSON export

## Phase Details

### Phase 5: Privacy-Aware Export
**Goal**: Users can export event logs without exposing personal location history
**Depends on**: Phase 4 (JSON export must exist)
**Requirements**: EXPT-01, EXPT-02, EXPT-03
**Success Criteria** (what must be TRUE):
  1. User sees an "Omit location data" toggle in the export UI before sharing JSON
  2. When the toggle is on, the shared JSON file contains no latitude or longitude values for any event
  3. When the toggle is off, the shared JSON file contains latitude and longitude as before
  4. The toggle remembers the user's last choice after quitting and relaunching the app
**Plans:** 1 plan

Plans:
- [x] 05-01-PLAN.md — Privacy toggle with conditional location encoding in export

## Progress

**Execution Order:**
Phases execute in numeric order.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.0 | 1/1 | Complete | 2026-03-25 |
| 2. Core Monitoring | v1.0 | 2/2 | Complete | 2026-03-25 |
| 3. Background Lifecycle | v1.0 | 3/3 | Complete | 2026-03-25 |
| 4. UI and Evidence Export | v1.0 | 3/3 | Complete | 2026-03-25 |
| 5. Privacy-Aware Export | v1.1 | 0/1 | Not started | - |
