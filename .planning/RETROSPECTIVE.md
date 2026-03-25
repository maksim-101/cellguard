# Retrospective

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-25
**Phases:** 4 | **Plans:** 9 | **Tasks:** 17

### What Was Built
- SwiftData ConnectivityEvent model with 15+ metadata fields and background @ModelActor persistence
- ConnectivityMonitor with NWPathMonitor path classification, 500ms debounce, and drop duration tracking
- HEAD probe to captive.apple.com every 60s with silent modem failure detection
- CoreTelephony radio technology and carrier capture
- LocationService (CLLocationManager + CLServiceSession) for persistent background execution
- Gap detection for monitoring coverage transparency
- MonitoringHealthService aggregating Low Power Mode, BAR, and location auth states
- ProvisioningProfileService with 48-hour expiry warning notification
- Dashboard with health bar, drop counts, Swift Charts timeline, and JSON export
- Summary report with drop statistics for Apple Feedback Assistant

### What Worked
- Evidence pipeline architecture (schema → detection → background → UI) gave clean phase boundaries with no rework
- Parallel executor agents in Wave 1 of Phase 4 saved time — independent plans (navigation + notifications) executed simultaneously
- SwiftData + @ModelActor pattern handled background writes cleanly from the start
- Significant location changes strategy provided reliable 24h+ background execution without battery drain concerns

### What Was Inefficient
- Phase completion tracking in ROADMAP.md progress table didn't update automatically — showed "Planning complete" even after execution
- CTCarrier deprecation uncertainty required defensive "Unknown" fallbacks throughout; could have decided this once upfront

### Patterns Established
- `isDropEvent()` shared classifier prevents drop-detection logic duplication across views
- Wake-then-probe pattern: significant location change wakes app → probe runs → event logged
- Health enum (active/degraded/paused) aggregates multiple iOS state signals into one UI indicator

### Key Lessons
- Silent modem failure detection is the differentiator — NWPathMonitor alone misses the "attached but unreachable" state
- Free personal team signing works fine for personal diagnostic tools; 7-day cycle is manageable
- iOS background execution is the hardest part — significant location changes is the only reliable free-tier approach

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 4 |
| Plans | 9 |
| Tasks | 17 |
| LOC (Swift) | 2,332 |
| Duration | 1 day |
