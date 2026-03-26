# Requirements: CellGuard

**Defined:** 2026-03-26
**Core Value:** Reliably detect and log every cellular connectivity drop — including the "attached but unreachable" silent modem failure — so there is irrefutable evidence for Apple's engineering team.

## v1.1 Requirements

Requirements for privacy-aware export. Each maps to roadmap phases.

### Export Privacy

- [ ] **EXPT-01**: User can toggle "Omit location data" before exporting JSON
- [ ] **EXPT-02**: When privacy toggle is on, exported JSON excludes latitude and longitude fields from all events
- [ ] **EXPT-03**: Privacy toggle state persists across app launches

## Future Requirements

None identified.

## Out of Scope

| Feature | Reason |
|---------|--------|
| CSV export privacy mode | No CSV export exists in the app |
| Redacting horizontalAccuracy | Not sensitive — just a radius in meters, reveals nothing about location |
| Per-field granular privacy controls | Over-engineering for a single toggle use case |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| EXPT-01 | — | Pending |
| EXPT-02 | — | Pending |
| EXPT-03 | — | Pending |

**Coverage:**
- v1.1 requirements: 3 total
- Mapped to phases: 0
- Unmapped: 3 ⚠️

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after initial definition*
