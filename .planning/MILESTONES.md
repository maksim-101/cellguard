# Milestones

## v1.2 Persistent Signing & Wi-Fi Context (Shipped: 2026-04-21)

**Phases completed:** 3 phases (6, 6.1, 7), 3 plans, 5 tasks

**Key accomplishments:**

- Paid Apple Developer team signing (Team VTWHBCCP36) replaces 7-day free personal team re-sign cycle
- ProvisioningProfileService adapted for 1-year certificate expiry with 7-day warning notification; "Cert Expires:" shows real date on device
- iOS 26 provisioning profile parsing fixed (non-ASCII CMS wrapper) and all Xcode warnings resolved
- Wi-Fi SSID captured on every connectivity event via NEHotspotNetwork.fetchCurrent(), stored in SwiftData, displayed in event detail, privacy-gated in JSON export
- Export filename now includes privacy toggle suffix (_privacyon/_privacyoff)

---

## v1.1 Privacy Export (Shipped: 2026-03-26)

**Phases completed:** 1 phases, 1 plans, 2 tasks

**Key accomplishments:**

- Privacy toggle strips latitude/longitude/locationAccuracy from JSON export via CodingUserInfoKey encoder flag with @AppStorage persistence

---

## v1.0 MVP (Shipped: 2026-03-25)

**Phases completed:** 4 phases, 9 plans, 17 tasks

**Key accomplishments:**

- SwiftData ConnectivityEvent model with 15+ DAT-01 metadata fields, EventStore @ModelActor for background writes, and buildable Xcode project shell
- ConnectivityMonitor coordinator with 4-case path classification, 500ms debounce, drop duration tracking, and EventStore persistence
- HEAD probe to captive.apple.com every 60s with silent modem failure detection, CoreTelephony radio/carrier capture, and full app lifecycle wiring
- LocationService with CLLocationManager + CLServiceSession for persistent background execution, gap detection via UserDefaults timestamps, and AppDelegate for location-based relaunch handling
- MonitoringHealthService aggregates Low Power Mode, Background App Refresh, and location auth into reactive Health enum; ProvisioningProfileService detects 7-day profile expiry and schedules 48-hour warning notification
- Full lifecycle wiring connecting LocationService, MonitoringHealthService, and ProvisioningProfileService into CellGuardApp with health status bar UI and HealthDetailSheet
- Dashboard with health bar, drop counts (24h/7d/total), connectivity state, plus event list and detail views with full metadata display
- Local drop notification with sysdiagnose prompt and Transferable JSON export model for ShareLink
- Summary report with drop statistics, Swift Charts timeline with silent/overt distinction, and ShareLink JSON export wired into scrollable dashboard

---
