# Requirements: CellGuard

**Defined:** 2026-03-25
**Core Value:** Reliably detect and log every cellular connectivity drop — including silent modem failures — to produce irrefutable evidence for Apple's engineering team.

## v1 Requirements

### Monitoring

- [x] **MON-01**: App monitors network path changes in real-time via NWPathMonitor and logs every transition (satisfied/unsatisfied/requiresConnection, interface changes)
- [x] **MON-02**: App performs periodic active connectivity probe (HEAD request to Apple captive portal) to detect silent modem failures where path reports "satisfied" but no data transits
- [x] **MON-03**: App classifies a probe timeout while path status is "satisfied" as a distinct "silent modem failure" event type
- [x] **MON-04**: App captures radio access technology (LTE, 5G NR, etc.) via CTTelephonyNetworkInfo with each event
- [x] **MON-05**: App captures carrier metadata (carrier name, MCC/MNC) on a best-effort basis (may be nil due to CTCarrier deprecation)
- [x] **MON-06**: App detects and logs when device silently falls back to Wi-Fi after a cellular drop (interface transition from cellular to Wi-Fi)
- [ ] **MON-07**: App prompts user via local notification to trigger sysdiagnose immediately after a drop is detected (for Apple baseband logging profile capture)

### Data & Storage

- [x] **DAT-01**: Each event is stored with full metadata: ISO 8601 timestamp (local + UTC), event type, path status, interface type, is_expensive, is_constrained, radio technology, carrier name, probe result (latency or failure reason), coarse location
- [x] **DAT-02**: App calculates and stores drop duration (time from drop-start event to next connectivity restoration event)
- [ ] **DAT-03**: App persists monitoring-enabled state across app kills, iOS terminations, and device reboots — auto-resumes monitoring on relaunch
- [x] **DAT-04**: App captures coarse location (via significant location changes) with each event for geographic pattern analysis
- [ ] **DAT-05**: App tracks and records monitoring gaps (periods when iOS suspended/terminated the app and no events could be captured)
- [x] **DAT-06**: App stores weeks of event data locally without significant storage impact using SwiftData

### Background Execution

- [ ] **BKG-01**: App uses significant location change monitoring (CLLocationManager) as primary background wake trigger and location source
- [ ] **BKG-02**: App retains an active CLServiceSession for background location delivery on iOS 18+
- [ ] **BKG-03**: App uses BGAppRefreshTask for supplementary background wake events
- [ ] **BKG-04**: App detects and warns user when Background App Refresh is disabled, Low Power Mode is active, or other conditions prevent reliable background monitoring
- [ ] **BKG-05**: App runs in background for 24+ hours without being terminated by iOS or causing noticeable battery drain

### User Interface

- [ ] **UI-01**: Dashboard view shows: monitoring active/paused status, current connectivity state, drop count (24h / 7d / total), last drop timestamp
- [ ] **UI-02**: Scrollable event log displays all captured events in reverse chronological order
- [ ] **UI-03**: Event detail view shows all captured metadata for a single event
- [ ] **UI-04**: App launches directly to dashboard with no onboarding beyond required permission prompts (location)

### Export & Reporting

- [ ] **EXP-01**: User can export full event log as structured JSON file via iOS Share Sheet
- [ ] **EXP-02**: App generates a summary report with: total drops, drops by type (overt vs silent), average/max duration, drops per day, location distribution, radio technology distribution
- [ ] **EXP-03**: App displays a timeline visualization (Swift Charts) showing drops over time with silent failures marked distinctly

## v2 Requirements

### Enhanced Evidence

- **ENH-01**: CSV export as alternative format alongside JSON
- **ENH-02**: Drop-free streak tracking (longest period without a drop)
- **ENH-03**: Annotation support — user can add notes to individual events (e.g., "was on a call when this happened")
- **ENH-04**: iOS version tracking per event (detect if drops correlate with specific updates)

### Notifications

- **NOT-01**: Local notification on every detected drop (for real-time awareness)
- **NOT-02**: Configurable notification frequency (every drop, daily summary, off)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Signal strength (dBm/RSSI) | Apple does not expose to third-party apps |
| Airplane Mode toggle (auto-recovery) | Not available via public iOS APIs |
| Cloud storage / external data transmission | Privacy constraint — all data stays on device |
| User accounts / authentication | Single-user personal tool |
| Continuous GPS tracking | Excessive battery drain; coarse location sufficient |
| Push notifications via server | Requires backend infrastructure; local notifications suffice |
| Packet-level network analysis | iOS sandboxing prevents packet capture; probe-based detection sufficient |
| Speed testing | Measures throughput not connectivity; probe detects failure state |
| Wi-Fi SSID capture | Requires paid developer program entitlement |
| App Store distribution | Personal diagnostic tool |
| Widgets / Watch complications | Adds complexity without improving bug report evidence |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MON-01 | Phase 2 | Complete |
| MON-02 | Phase 2 | Complete |
| MON-03 | Phase 2 | Complete |
| MON-04 | Phase 2 | Complete |
| MON-05 | Phase 2 | Complete |
| MON-06 | Phase 2 | Complete |
| MON-07 | Phase 4 | Pending |
| DAT-01 | Phase 1 | Complete |
| DAT-02 | Phase 2 | Complete |
| DAT-03 | Phase 3 | Pending |
| DAT-04 | Phase 2 | Complete |
| DAT-05 | Phase 3 | Pending |
| DAT-06 | Phase 1 | Complete |
| BKG-01 | Phase 3 | Pending |
| BKG-02 | Phase 3 | Pending |
| BKG-03 | Phase 3 | Pending |
| BKG-04 | Phase 3 | Pending |
| BKG-05 | Phase 3 | Pending |
| UI-01 | Phase 4 | Pending |
| UI-02 | Phase 4 | Pending |
| UI-03 | Phase 4 | Pending |
| UI-04 | Phase 4 | Pending |
| EXP-01 | Phase 4 | Pending |
| EXP-02 | Phase 4 | Pending |
| EXP-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation — all 25 requirements mapped*
