# Requirements: CellGuard

**Defined:** 2026-04-20
**Core Value:** Reliably detect and log every cellular connectivity drop — including the "attached but unreachable" silent modem failure — so there is irrefutable evidence for Apple's engineering team.

## v1.2 Requirements

Requirements for v1.2 Persistent Signing & Wi-Fi Context. Each maps to roadmap phases.

### Signing

- [ ] **SIGN-01**: App is signed with paid Apple Developer team (Team ID VTWHBCCP36) instead of free personal team
- [ ] **SIGN-02**: App remains installed on device indefinitely without requiring re-deployment every 7 days

### Expiry Monitoring

- [ ] **EXPR-01**: ProvisioningProfileService detects the 1-year distribution certificate expiry date
- [ ] **EXPR-02**: User receives a local notification 7 days before certificate expiry

### Wi-Fi Context

- [x] **WIFI-01**: Current Wi-Fi SSID is captured at the time of each connectivity event
- [x] **WIFI-02**: Wi-Fi SSID is stored as a field in the SwiftData ConnectivityEvent model
- [x] **WIFI-03**: Wi-Fi SSID is included in JSON and CSV export output, respecting the existing privacy toggle (stripped when privacy mode is enabled)
- [x] **WIFI-04**: Wi-Fi SSID is visible in the event detail view

## Future Requirements

### Potential Enhancements

- **FUTR-01**: Widget showing current connectivity status and recent drop count
- **FUTR-02**: Export filtering by date range or event type
- **FUTR-03**: Export filename reflects privacy toggle state (e.g., `_privacyon` / `_privacyoff` suffix)

## Out of Scope

| Feature | Reason |
|---------|--------|
| App Store distribution | Personal diagnostic tool, not for public distribution |
| TestFlight distribution | Single-user tool, direct Xcode deployment sufficient |
| Cloud backup of events | All data stays local — no external transmission |
| Push notifications (remote) | No server infrastructure; local notifications only |
| Automatic certificate renewal | Requires manual Apple Developer portal interaction |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SIGN-01 | Phase 6 | Pending |
| SIGN-02 | Phase 6 | Pending |
| EXPR-01 | Phase 6 | Pending |
| EXPR-02 | Phase 6 | Pending |
| WIFI-01 | Phase 7 | Complete |
| WIFI-02 | Phase 7 | Complete |
| WIFI-03 | Phase 7 | Complete |
| WIFI-04 | Phase 7 | Complete |

**Coverage:**
- v1.2 requirements: 8 total
- Mapped to phases: 8
- Unmapped: 0

---
*Requirements defined: 2026-04-20*
*Last updated: 2026-04-20 after roadmap creation*
