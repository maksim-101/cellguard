# Feature Landscape

**Domain:** iOS cellular connectivity drop logger / diagnostic evidence tool
**Researched:** 2026-03-25
**Confidence:** MEDIUM-HIGH (iOS API capabilities well-documented; gap in direct signal strength access is a confirmed platform limitation)

## Context

CellGuard is not a general network monitoring app. It is a single-purpose diagnostic tool whose output audience is Apple's engineering team via Feedback Assistant. Every feature decision should be evaluated through the lens: "Does this make the bug report more convincing or the evidence more actionable?"

The target bug -- iPhone 17 Pro Max baseband modem failing to recover after signal loss, including a "silent" variant where NWPathMonitor reports "satisfied" but no data transits -- requires a specific evidence strategy that general network monitoring apps do not address.

---

## Table Stakes

Features that are essential for the app to fulfill its core purpose. Without these, the bug report evidence is incomplete or unconvincing.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **NWPathMonitor real-time monitoring** | Detects path status changes (satisfied/unsatisfied/requiresConnection) and interface transitions (cellular/wifi/none). This is the primary detection mechanism for overt drops. | Low | Built-in iOS Network framework. Runs on background queue. Fires callbacks on every path change. |
| **Periodic active connectivity probe** | Detects the "silent" modem failure where path reports "satisfied" but no data transits. HEAD request to `apple.com/library/test/success.html` (Apple's own captive portal endpoint). | Medium | 60-second interval balances detection latency with battery. Must handle timeout vs failure vs success states. Must work in background. Core differentiator vs passive-only monitoring. |
| **Structured event logging with metadata** | Each drop event needs: timestamp (ISO 8601), event type, path status before/after, interface type, radio access technology (via CTTelephonyNetworkInfo), carrier name, probe result, drop duration, location. Without metadata, Apple engineering cannot correlate with baseband logs. | Medium | SwiftData or SQLite. Schema must be stable -- changing it mid-collection invalidates earlier data. Design the schema once, correctly. |
| **Background execution (24+ hours)** | Drops happen unpredictably across the day. A tool that only logs when foregrounded misses most events and produces unconvincing evidence. | High | Hardest feature. Combine: (1) significant location change monitoring for background wake eligibility, (2) NWPathMonitor background delivery, (3) BGAppRefreshTask for periodic probes. Must survive iOS process management. Test extensively. |
| **CSV/JSON export** | Feedback Assistant accepts file attachments. Structured data (not screenshots) is what Apple engineering needs. CSV for spreadsheet analysis, JSON for programmatic consumption. | Low | Straightforward serialization from SwiftData/SQLite. Include all metadata fields. Use ISO 8601 timestamps. |
| **Minimal dashboard UI** | Current status at a glance: monitoring active/paused, current connectivity state, drop count (24h / 7d / total), last drop timestamp. Without this, you cannot confirm the app is actually working. | Low | Single SwiftUI view. Real-time updates via Combine/observation. |
| **Scrollable event log** | Browse captured events chronologically. Essential for spot-checking that detection is working correctly and events have complete metadata. | Low | SwiftUI List with SwiftData query. Newest-first ordering. |
| **Event detail view** | Tap any event to see full metadata. Needed to verify data quality before submitting to Apple. | Low | Simple detail view displaying all fields of a single event record. |
| **Drop duration tracking** | Measures time from drop detection to connectivity restoration. Critical evidence: "average drop lasted 4 minutes, longest was 23 minutes." Duration patterns help Apple distinguish modem firmware hangs from transient signal issues. | Medium | Requires correlating drop-start and recovery-detected events. Timer logic must handle the app being backgrounded during a drop. |
| **Monitoring state persistence** | App must resume monitoring after iOS kills and relaunches it, after device reboot, or after the 7-day re-signing cycle. | Medium | Persist monitoring-enabled state in UserDefaults. Auto-start on launch. Handle the significant-location-change relaunch path in AppDelegate/SceneDelegate. |

---

## Differentiators

Features that elevate the bug report from "user complaint" to "engineering-grade diagnostic evidence." Not strictly required, but significantly increase the chances Apple acts on the report.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Silent failure detection (probe-based)** | The killer feature. Most network monitors only watch NWPathMonitor status. The iPhone 17 bug specifically involves a state where the path reports "satisfied" but the modem is unreachable. Detecting this requires active probing. No App Store network monitor does this. | Medium | Already listed as table stakes for the probe itself, but the detection logic -- classifying a probe timeout while path is "satisfied" as a silent modem failure event type -- is the true differentiator. Needs careful timeout tuning (10-15 seconds) to avoid false positives on slow networks. |
| **Coarse location per event** | Geographic pattern analysis: "drops cluster at location X" or "drops happen everywhere, ruling out coverage." Apple engineering can correlate with cell tower databases. | Medium | Use significant location change monitoring (CLLocationManager). Coarse accuracy is sufficient and battery-friendly. Doubles as background execution eligibility. Store lat/lon rounded to 3 decimal places (~100m precision). |
| **Summary report generation** | Auto-generated narrative: "Over 14 days, CellGuard recorded 47 connectivity drops averaging 3.2 minutes each. 12 were silent modem failures (path satisfied, probe failed). Drops occurred across 8 distinct locations..." This is the cover letter for the Feedback Assistant report. | Medium | Aggregate queries against the event database. Template-based text generation. Include: total drops, drops by type, average/max duration, drops per day trend, location count, radio technology distribution. |
| **Timeline visualization (Swift Charts)** | A chart showing drops over time makes patterns immediately visible: "drops cluster at 2-4 AM" or "drops increased after iOS 26.3 update." Visual evidence is compelling. | Medium | Swift Charts (iOS 16+). Line/bar chart with time on X axis, drops per hour/day on Y. Mark silent failures distinctly. Annotation for iOS version changes if tracked. |
| **Sysdiagnose timing integration** | When a drop is detected, prompt or log the ideal window to trigger a sysdiagnose (within minutes of the event). Apple's baseband logging profile captures modem state, but only if sysdiagnose is triggered promptly. | Low | Local notification on drop detection: "Connectivity drop detected. Trigger sysdiagnose now for Apple diagnostics." Include instructions. Optionally log whether sysdiagnose was triggered. |
| **Radio access technology tracking** | Log the RAT (LTE, 5G NR, 5G NSA, UMTS, etc.) at each event via CTTelephonyNetworkInfo. Pattern: "drops only happen on 5G" or "drops happen across all RATs" narrows the bug to modem vs. specific radio stack. | Low | CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology. Available without special entitlements. Log with each event. |
| **Carrier and SIM metadata** | Log carrier name, MCC/MNC, ISO country code. Eliminates carrier-specific explanations: "same bug on Swisscom (228-01) and Sunrise (228-02)." | Low | CTTelephonyNetworkInfo.serviceSubscriberCellularProviders. Capture once at startup and on changes. |
| **Drop-free streak tracking** | "Longest period without a drop: 4 hours 12 minutes." Contextualizes frequency. Shows the bug is not constant but intermittent, which is consistent with a state-machine race condition. | Low | Derived from event timestamps. No additional data collection needed. |
| **Wi-Fi fallback detection** | Detect when the device silently falls back to Wi-Fi after a cellular drop. This masks the cellular issue from the user but is important evidence: "device fell back to Wi-Fi 30 seconds after cellular became unreachable." | Low | NWPathMonitor already reports available interfaces. Log interface transitions alongside connectivity events. |
| **Notification on drop detection** | Local notification when a drop is detected so user can (1) confirm subjective experience matches logged event, (2) trigger sysdiagnose promptly. | Low | UNUserNotificationCenter. Fire on confirmed drop event. Include event type and timestamp in notification body. |

---

## Anti-Features

Features to explicitly NOT build. Each would add complexity without improving the bug report or would be technically impossible / counterproductive.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Signal strength (dBm/RSSI) display** | Apple does not expose signal strength to third-party apps. Private APIs would require jailbreak or entitlements unavailable on free signing. Field Test Mode (*3001#12345#*) exists but is not programmatically accessible. | Note in the bug report that signal strength data is unavailable to third-party apps; reference Field Test Mode screenshots taken manually during drops if desired. |
| **Automatic Airplane Mode toggle (recovery)** | Not possible via public iOS APIs. No third-party app can toggle Airplane Mode. Attempting private API usage would cause App Store rejection (irrelevant here) and potentially crash or get the app killed by iOS. | Log the drop event; user manually toggles Airplane Mode. Log the recovery event and duration. |
| **Cloud sync / external data transmission** | Violates the privacy constraint. Adds infrastructure complexity for a single-user tool. No benefit for the bug report. | All data stays on-device. Export via Share Sheet when needed. |
| **User accounts / authentication** | Single-user personal tool deployed via Xcode. Authentication adds zero value and significant complexity. | No auth. App launches directly to dashboard. |
| **Continuous GPS tracking** | Massive battery drain. Defeats the "unnoticeable battery impact" constraint. Coarse location from significant location changes is sufficient for pattern analysis. | Use significant location change monitoring only. ~100m precision is more than adequate for "which neighborhood/city" analysis. |
| **Push notifications via server** | Requires a backend, APNs certificate, server infrastructure. Local notifications achieve the same goal (alerting user to drops) with zero infrastructure. | Use UNUserNotificationCenter for local notifications only. |
| **Packet-level network analysis** | iOS sandboxing prevents packet capture without a VPN configuration profile. Adds massive complexity. Not needed -- the bug is at the modem/baseband layer, not the application layer. | Rely on probe-based connectivity checks and NWPathMonitor status. The probe timeout IS the evidence of packet-level failure. |
| **Speed testing** | Measures throughput, not connectivity. A speed test during a silent modem failure would simply timeout/fail, which the probe already detects. Adds bandwidth consumption and complexity. | The HEAD probe to Apple's captive portal is the minimal, battery-efficient equivalent. |
| **Wi-Fi SSID capture** | Requires CNCopyCurrentNetworkInfo entitlement, which requires paid Apple Developer Program membership or specific entitlement approval. Not available on free personal team signing. | Log that the device was on Wi-Fi (NWPathMonitor provides this) without capturing the specific SSID. |
| **Elaborate onboarding / tutorial** | Single user who is also the developer. Zero onboarding needed. | App launches to dashboard. One-time location permission prompt. Done. |
| **Historical data sync across devices** | Single device (iPhone 17 Pro Max) is the subject of the bug report. No other device needs the data. | Single-device, single-database design. |
| **Widgets / Watch complications** | Nice-to-have but adds significant complexity for minimal diagnostic value. The bug report does not benefit from a widget. | Focus development time on reliable background monitoring and accurate event logging. |

---

## Feature Dependencies

```
NWPathMonitor monitoring ─┬─> Event logging ──> Event list UI ──> Event detail view
                          │                  ├─> CSV/JSON export
                          │                  ├─> Summary report generation
                          │                  └─> Timeline visualization (Swift Charts)
                          │
                          ├─> Dashboard UI (current status, counts)
                          │
                          └─> Drop duration tracking ──> Drop-free streak tracking

Periodic connectivity probe ──> Silent failure detection ──> Event logging (same pipeline)

Significant location changes ─┬─> Coarse location per event
                              └─> Background execution eligibility

Background execution ──> Monitoring state persistence
                     ──> Significant location changes (enabler)
                     ──> BGAppRefreshTask (periodic probe in background)

Event logging ──> Local notification on drop

Local notification on drop ──> Sysdiagnose timing prompt
```

### Critical Path

The dependency chain that must work first:

1. **NWPathMonitor + periodic probe** (detection layer)
2. **Event logging with metadata** (storage layer)
3. **Background execution** (reliability layer -- without this, detection is intermittent)
4. **Export** (output layer -- the deliverable for Feedback Assistant)

Everything else (UI, charts, reports, notifications) is built on top of these four layers.

---

## MVP Recommendation

### Must ship in v1 (core evidence pipeline):

1. NWPathMonitor real-time monitoring with event logging
2. Periodic active connectivity probe (silent failure detection)
3. Structured event storage (SwiftData) with full metadata schema
4. Background execution via significant location changes + BGAppRefreshTask
5. Dashboard UI (status, counts)
6. Event list + detail views
7. CSV export

### Ship in v1.1 (evidence quality improvements):

1. Summary report generation (narrative for Feedback Assistant)
2. JSON export (alongside CSV)
3. Local notifications on drop detection
4. Sysdiagnose timing prompt
5. Timeline visualization (Swift Charts)

### Defer (nice-to-have, build if time permits):

- Drop-free streak tracking (derived metric, easy to add later)
- Wi-Fi fallback detection (implicit in NWPathMonitor data, formalize later)

---

## Key Insight: What Makes This Different From Existing Apps

Existing iOS network monitoring apps (Network Analyzer, LTE Cell Info, Cellular Network Signal Finder) focus on:
- Signal strength visualization (which Apple restricts for third-party apps)
- Speed testing
- Cell tower identification
- Wi-Fi analysis

None of them:
1. **Actively probe for silent modem failures** (path "satisfied" but unreachable)
2. **Run continuous background monitoring for days/weeks**
3. **Produce structured evidence formatted for Apple engineering consumption**
4. **Correlate connectivity events with location, RAT, and temporal patterns**

CellGuard's value is not in monitoring -- it is in **evidence production**. Every feature should serve the goal of making the Feedback Assistant report undeniable.

---

## Sources

- [Apple NWPathMonitor Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [Apple Feedback Assistant - Bug Reporting](https://developer.apple.com/bug-reporting/)
- [Apple Profiles and Logs for Bug Reports](https://developer.apple.com/bug-reporting/profiles-and-logs/?platform=ios)
- [Apple Swift Charts Documentation](https://developer.apple.com/documentation/Charts)
- [MacRumors: iPhone 17 Pro/Pro Max Cellular Modem Failure Thread](https://forums.macrumors.com/threads/iphone-17-pro-pro-max-fixed-cellular-modem-fails-to-recover-after-signal-loss.2474315/)
- [Apple Energy Efficiency Guide - Location Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)
- [Apple Background Location Handling](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Mastering iOS Background Modes (Medium)](https://mohsinkhan845.medium.com/mastering-ios-background-modes-and-tasks-a-comprehensive-guide-322116db13fd)
