# Milestones

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
