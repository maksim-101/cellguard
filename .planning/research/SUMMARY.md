# Project Research Summary

**Project:** CellGuard
**Domain:** iOS background cellular connectivity monitoring / diagnostic evidence tool
**Researched:** 2026-03-25
**Confidence:** MEDIUM-HIGH

## Executive Summary

CellGuard is a single-purpose diagnostic tool for producing engineering-grade evidence of a specific iPhone 17 Pro Max baseband modem bug: a failure to recover after signal loss, including a "silent" variant where `NWPathMonitor` reports `satisfied` but no data transits. This is not a general network monitor — every feature decision must be evaluated against one question: does this make the Feedback Assistant report more convincing? The entire product value proposition rests on active probe-based detection (a HEAD request to Apple's captive portal endpoint) combined with continuous background monitoring, producing structured CSV/JSON output formatted for Apple engineering consumption.

The recommended approach is an all-Apple-native stack: Swift 6.2, SwiftUI, SwiftData, NWPathMonitor, CoreLocation (significant location changes), CoreTelephony, and Swift Charts. No third-party dependencies are warranted. The architecture is a layered actor-based system: three framework-wrapper services feeding a MonitoringCoordinator that assembles complete event records, persisted via a ModelActor EventStore, surfaced in SwiftUI views via `@Query`. Background execution is the hardest problem and the most critical architectural decision — the only reliable mechanism that relaunches a terminated app is `startMonitoringSignificantLocationChanges()`, which must be combined with `BGAppRefreshTask` and an active HEAD probe on every wake event.

The primary risk is building a system that works flawlessly in the foreground but fails silently in the background. iOS aggressively suspends apps and provides no guaranteed sub-minute periodic execution mechanism outside of continuous GPS (which is unacceptable for battery reasons). The architecture must be designed for event-driven background monitoring from day one — retrofitting is expensive. A secondary risk is the 7-day free provisioning expiration creating data gaps and undermining evidence credibility. Both risks are manageable with correct upfront architectural choices and user-facing monitoring health indicators.

---

## Key Findings

### Recommended Stack

The entire stack is first-party Apple frameworks, which is both appropriate and necessary given free personal team signing constraints (no entitlements that require a paid developer account). Swift 6.2's approachable concurrency model and strict concurrency checking make the actor-based architecture tractable. SwiftData is chosen over GRDB.swift because the data volume (~1,440 events/day) does not justify an external dependency. `BGContinuedProcessingTask` (new in iOS 26) is available for user-initiated export of large datasets.

**Core technologies:**
- **Swift 6.2 / SwiftUI (iOS 26 SDK):** Language and UI — strict concurrency catches data races at compile time; SwiftUI `@Observable` and `@Query` provide reactive UI with minimal boilerplate
- **NWPathMonitor (Network framework):** Passive path change detection — fires callbacks on interface transitions; supplements active probe but cannot survive app suspension alone
- **URLSession HEAD probe:** Active silent failure detection — 10-second timeout HEAD to `apple.com/library/test/success.html`; the only way to detect "attached but unreachable" modem state
- **CoreLocation significant location changes:** Background keep-alive — near-zero battery cost; the ONLY mechanism that relaunches a terminated app; provides coarse location (~500m) as a bonus
- **CoreTelephony (`CTTelephonyNetworkInfo`):** Radio access technology metadata — `serviceCurrentRadioAccessTechnology` still works in iOS 26; `CTCarrier` is deprecated with no replacement, so carrier name is best-effort
- **SwiftData with `@ModelActor`:** Local event persistence — native SwiftUI integration, adequate performance for this data volume, thread-safe background writes via ModelActor
- **Swift Charts:** Drop visualization — `BarMark`/`LineMark` cover all needed chart types; no external dependency
- **BGAppRefreshTask + BGContinuedProcessingTask:** Supplemental background execution and user-initiated export respectively

**What NOT to use:** Combine (maintenance mode), `CLMonitor` (documented crash bugs), Continuous GPS (battery killer), `ObservableObject`/`@Published` (legacy), background `URLSession` for periodic checks (wrong API), `Timer` in background (suspended by iOS), `CTCarrier` (deprecated iOS 16.4).

### Expected Features

CellGuard's feature set is evidence-production-driven, not consumer-app-driven. The must-have features define the evidence pipeline; everything else improves evidence quality.

**Must have (table stakes) — v1:**
- NWPathMonitor real-time monitoring with structured event logging — primary detection mechanism for overt drops
- Periodic active connectivity probe (HEAD request) — the killer feature; detects silent modem failures that NWPathMonitor misses
- Full metadata schema per event: timestamp, event type, path status, interface type, radio access tech, carrier, probe result, drop duration, coarse location — without this, Apple cannot correlate with baseband logs
- Background execution (24+ hours) via significant location changes + BGAppRefreshTask — drops happen unpredictably; foreground-only monitoring produces unconvincing evidence
- Dashboard UI: monitoring status, drop counts (24h/7d/total), last drop timestamp
- Event list and detail views — spot-check data quality before submission
- CSV export — structured file attachment for Feedback Assistant
- Drop duration tracking — "average drop lasted 4 minutes" is compelling evidence
- Monitoring state persistence — auto-restart after iOS kill/reboot/7-day re-sign

**Should have (evidence quality) — v1.1:**
- Summary report generation — auto-generated narrative for Feedback Assistant cover letter
- JSON export alongside CSV
- Timeline visualization (Swift Charts) — visual pattern evidence ("drops cluster at 2-4 AM")
- Local notification on drop + sysdiagnose timing prompt — critical window for capturing baseband diagnostics
- Drop-free streak tracking and Wi-Fi fallback detection

**Defer (v2+):**
- Widgets / Watch complications — no diagnostic value
- Elaborate onboarding — single developer-user
- Historical sync across devices — single-device tool

**Anti-features (never build):** Signal strength (private API), Airplane Mode toggle (impossible via public API), cloud sync, continuous GPS, Wi-Fi SSID capture (requires paid developer entitlement), packet-level analysis.

### Architecture Approach

The architecture follows a strict layered actor model: three thin iOS-framework wrapper services (ConnectivityMonitor, LocationService, TelephonyService) feed a MonitoringCoordinator actor that assembles complete ConnectivityEvent records. No service writes to the database directly and no service talks to another service — all orchestration flows through the coordinator. Persistence is a dedicated `@ModelActor` EventStore that handles all background writes; views read via SwiftData's `@Query` mechanism, never by calling EventStore directly. ViewModels are `@Observable @MainActor` classes that bridge the coordinator state to SwiftUI.

**Major components:**
1. **ConnectivityMonitor (actor)** — wraps NWPathMonitor on a dedicated DispatchQueue + 60s periodic HEAD request via Swift concurrency Task loop
2. **LocationService (actor)** — wraps CLLocationManager + CLServiceSession; provides coarse last-known location and serves as the background keep-alive mechanism
3. **TelephonyService (thin wrapper)** — reads radio access technology and carrier info from CTTelephonyNetworkInfo on demand; all values Optional
4. **MonitoringCoordinator (actor)** — orchestrates all three services; assembles ConnectivityEvent records with all metadata; manages background lifecycle and monitoring gap tracking
5. **EventStore (@ModelActor)** — all SwiftData writes; provides FetchDescriptor-based query helpers for export and statistics
6. **MonitoringViewModel (@Observable @MainActor)** — drives dashboard UI; subscribes to coordinator state
7. **ExportViewModel (@Observable @MainActor)** — generates CSV/JSON from EventStore; manages ShareSheet flow
8. **SwiftUI Views** — pure presentation; `@Query` for live data; no business logic

**Key patterns:** Actor-based service isolation (thread safety by construction), coordinator as event assembler (prevents partial records), ModelActor for background writes (no main-thread SwiftData writes), monitoring gap tracking (log start/stop events so absence-of-events means "not watching," not "no drops").

### Critical Pitfalls

1. **NWPathMonitor stops when app is suspended** — NWPathMonitor is in-process only; it delivers no callbacks while the app is suspended. Must combine with significant location changes for background keep-alive and run a HEAD probe on every wake event. Testing foreground-only will produce false confidence.

2. **60-second background timer is impossible** — iOS provides no guaranteed sub-minute periodic execution in the background. Accept event-driven monitoring: probe on every significant location change and BGAppRefreshTask wake. Log "last checked" timestamp so gaps are visible in exported data.

3. **NWPathMonitor reports `satisfied` during silent modem failures** — the specific bug being documented involves a state where the path appears connected but data does not transit. NWPathMonitor alone will NEVER detect this. Every wake must perform an active HEAD check; classify `satisfied` + HEAD failure as `silentFailure` event type.

4. **Significant location changes stop silently** — Background App Refresh disabled (by user, Low Power Mode, or iOS heuristics) will silently halt background wakes. Must check `backgroundRefreshStatus` on every foreground launch, warn the user, and display a persistent monitoring health indicator (green/yellow/red).

5. **7-day free provisioning expiration** — profile expiry creates data gaps and undermines evidence credibility. Embed expiration date at build time, show countdown in UI, fire local notification 2 days before expiry. This is a known operational constraint with no technical workaround on free signing.

6. **CTCarrier deprecation** — `CTCarrier` returns nil/static values when built with iOS 16.4+ SDK. All CoreTelephony calls must return Optional; carrier name is supplementary metadata, not required for core functionality. Store raw radio technology strings rather than mapping to enums.

---

## Implications for Roadmap

Research identifies a clear dependency graph that dictates phase order. The evidence pipeline (detection → storage → export) must work reliably before any UI investment. Background lifecycle is architecturally foundational and cannot be retrofitted. The suggested 5-phase structure maps directly to the build order identified in ARCHITECTURE.md.

### Phase 1: Foundation and Data Model

**Rationale:** Everything depends on the ConnectivityEvent schema. Changing the schema after data is collected invalidates earlier data — the FEATURES.md research calls this out explicitly. Establish the data model and persistence layer first so all subsequent work builds on a stable foundation.
**Delivers:** SwiftData model (`ConnectivityEvent` with full metadata schema), EventStore ModelActor, App shell with ModelContainer setup, project structure scaffolding
**Addresses:** Structured event logging with metadata (table stakes), monitoring state persistence
**Avoids:** Timestamp-as-string anti-pattern, UserDefaults for event storage (both identified as unrecoverable technical debt in PITFALLS.md)
**Research flag:** Standard patterns — SwiftData @ModelActor is well-documented; no additional research needed

### Phase 2: Core Monitoring Services

**Rationale:** The three iOS framework wrappers are independent of each other and can be built in parallel. They are the lowest-level components with no UI dependencies. Getting detection logic correct before wiring to UI ensures the data being displayed is trustworthy.
**Delivers:** ConnectivityMonitor (NWPathMonitor + HEAD probe with silent failure classification), TelephonyService (CoreTelephony with Optional handling), LocationService (CLLocationManager + CLServiceSession), MonitoringCoordinator assembling all three into ConnectivityEvent records
**Addresses:** NWPathMonitor monitoring, periodic connectivity probe, silent failure detection, radio access technology tracking, coarse location per event
**Avoids:** NWPathMonitor-only architecture (Pitfall 3), storing NWPath objects (Architecture anti-pattern 4), CTCarrier hard dependency (Pitfall 6), single shared CTTelephonyNetworkInfo instance (integration gotcha)
**Research flag:** Standard patterns for NWPathMonitor and CoreTelephony; CLServiceSession (iOS 18+) is newer — verify behavior on iOS 26 during implementation

### Phase 3: Background Lifecycle and Reliability

**Rationale:** This is the hardest phase and the highest-risk. PITFALLS.md is emphatic: background execution must be designed correctly from the start; retrofitting is expensive. Build and test background behavior before building UI on top of it, so bugs are caught early.
**Delivers:** Significant location change background keep-alive, BGAppRefreshTask registration and handling, app relaunch detection (UIApplication.LaunchOptionsKey.location), monitoring gap tracking (start/stop event logging), backgroundRefreshStatus health checking, Low Power Mode detection, 7-day provisioning expiration tracking
**Addresses:** Background execution (24+ hours) table stakes, monitoring state persistence, provisioning expiration resilience
**Avoids:** Pitfalls 1, 2, 4, 5 (all background-lifecycle related), BGAppRefreshTask registration in both Info.plist and code (integration gotcha), CoreLocation two-step authorization flow
**Research flag:** NEEDS DEEPER RESEARCH — background execution behavior in iOS 26 with CLServiceSession, exact interaction between Low Power Mode and significant location changes, BGAppRefreshTask minimum frequency; test on physical device early

### Phase 4: Dashboard UI and Event Browsing

**Rationale:** By this phase, the monitoring pipeline is proven to work. UI can be built with confidence because the underlying data is real and reliable. The dashboard is pure presentation — `@Observable` ViewModels over `@Query` SwiftData results.
**Delivers:** Dashboard (monitoring status indicator green/yellow/red, drop counts 24h/7d/total, last drop timestamp), EventListView (newest-first, filterable), EventDetailView (full metadata), local notifications on drop detection, sysdiagnose timing prompt, permissions onboarding flow
**Addresses:** Dashboard UI, scrollable event log, event detail view, notification on drop, sysdiagnose integration, no-permission-onboarding UX pitfall
**Avoids:** Showing raw NWPath status strings (UX pitfall), no monitoring degradation indicator (UX pitfall), no permission onboarding (UX pitfall)
**Research flag:** Standard SwiftUI patterns; no additional research needed

### Phase 5: Export and Evidence Package

**Rationale:** Export is the final deliverable — the product of all prior phases. Building it last ensures the full data model is stable before designing the export format. A format change after data is collected is painful.
**Delivers:** CSV export (ShareLink + fileExporter), JSON export, date-range filtering for export, summary report generation (auto-generated narrative), Swift Charts timeline visualization (drops per hour/day, silent failures highlighted), BGContinuedProcessingTask for large exports
**Addresses:** CSV/JSON export (table stakes), summary report generation (differentiator), timeline visualization (differentiator), all v1.1 features
**Avoids:** Single massive CSV without filtering (UX pitfall), missing summary statistics in export, HEAD request timeout not propagated to export data
**Research flag:** Standard patterns for ShareLink/fileExporter and Swift Charts; BGContinuedProcessingTask is iOS 26-new — verify API in Xcode 26 SDK during implementation

### Phase Ordering Rationale

- **Data model before services:** Schema stability is non-negotiable (FEATURES.md). A changed schema invalidates existing data.
- **Services before background lifecycle:** Background lifecycle wraps around services; the coordinator must work in the foreground first before testing the background relaunch path.
- **Background lifecycle before UI:** Testing that background monitoring produces correct data requires reading console logs, not a polished UI. Build confidence in the data before building display surfaces.
- **UI before export:** Export format should reflect the final, stable data model and UI conventions (e.g., date formats, event type labels).
- **Silent failure detection in Phase 2, not Phase 3:** This is core detection logic, not a background-specific concern. It must be correct before any testing, including background testing.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Background Lifecycle):** iOS 26 background execution behavior is not fully documented; CLServiceSession interaction with significant location changes on iOS 26 needs validation on physical hardware; BGAppRefreshTask minimum practical frequency varies by device and usage pattern — empirical testing required
- **Phase 2 (Core Monitoring, minor):** CLServiceSession is iOS 18+ and the interaction with CLLocationManager's significant location changes API on iOS 26 should be verified in Xcode 26 SDK documentation before implementation

Phases with standard patterns (research-phase can be skipped):
- **Phase 1 (Foundation):** SwiftData @ModelActor pattern is thoroughly documented with multiple high-quality sources; implementation is straightforward
- **Phase 4 (Dashboard UI):** Pure SwiftUI with @Observable and @Query — well-established patterns in iOS 26 target
- **Phase 5 (Export):** ShareLink, fileExporter, Swift Charts BarMark/LineMark — all documented with code examples in existing research

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All first-party Apple frameworks with stable APIs; alternatives considered and ruled out with clear rationale; CTCarrier deprecation is known and handled |
| Features | MEDIUM-HIGH | Evidence pipeline is well-defined; anti-features are clearly scoped; the "silent failure" detection pattern is the novel element with no existing reference implementation to compare against |
| Architecture | HIGH | Actor-based layering follows documented Swift concurrency best practices; SwiftData ModelActor threading is confirmed in multiple independent sources; build order dependency graph is clear |
| Pitfalls | HIGH | iOS background execution constraints are well-documented in Apple Developer Forums; behavior has been consistent across iOS versions; specific failure modes are confirmed by community reports |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Silent failure timeout tuning:** The 10-15 second HEAD request timeout range is recommended, but the optimal value for distinguishing a genuine modem failure from a slow cell network requires empirical testing on the target device. Plan a calibration step in Phase 2 using real-world connectivity conditions.
- **CTTelephonyNetworkInfo on iOS 26:** `serviceCurrentRadioAccessTechnology` is confirmed functional through iOS 18, but behavior on iOS 26 with the iPhone 17 Pro Max modem should be verified early in Phase 2. If Apple has further restricted it, radio tech logging falls back to "Unknown."
- **CLServiceSession + significant location changes interaction:** This combination (required for iOS 18+) is newer and less battle-tested than the pre-iOS-18 path. One source notes that without an active CLServiceSession, background delivery may silently stop. Verify this on the target device in Phase 3.
- **BGAppRefreshTask practical frequency:** Research confirms the system is discretionary (15 min to hours), but actual frequency on iPhone 17 Pro Max with iOS 26 and typical usage patterns is unknown. The monitoring architecture correctly treats this as supplementary, but the gap analysis in exported data should set honest user expectations.
- **Provisioning expiration date embedding:** The mechanism for embedding the profile expiration date at build time (build script approach) needs implementation research — this is a build tooling problem, not an iOS API problem.

---

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation — NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- [Apple Developer Documentation — startMonitoringSignificantLocationChanges](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges())
- [Apple Developer Documentation — Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple Developer Documentation — Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)
- [Apple Developer Documentation — BGContinuedProcessingTask (iOS 26)](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [WWDC 2025 — Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/)
- [Apple Developer Documentation — CTTelephonyNetworkInfo](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo)
- [Apple Developer Documentation — Swift Charts](https://developer.apple.com/documentation/Charts)

### Secondary (MEDIUM confidence)
- [fatbobman.com — Key Considerations Before Using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [fatbobman.com — Concurrent programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)
- [useyourloaf.com — SwiftData Background Tasks](https://useyourloaf.com/blog/swiftdata-background-tasks/)
- [Hacking with Swift — SwiftData background context](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-background-context)
- [twocentstudios.com — Core Location Modern API Tips (CLServiceSession)](https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/)
- [avanderlee.com — Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [Apple Developer Forums — CTCarrier Deprecation](https://developer.apple.com/forums/thread/714876)
- [Apple Developer Forums — NWPathMonitor background behavior](https://developer.apple.com/forums/thread/662297)
- [Apple Developer Forums — Significant Location Change + BAR dependency](https://developer.apple.com/forums/thread/694081)
- [Apple Developer Forums — iOS Background Execution Limits](https://developer.apple.com/forums/thread/685525)
- [MacRumors — iPhone 17 Pro Max cellular modem failure thread](https://forums.macrumors.com/threads/iphone-17-pro-pro-max-fixed-cellular-modem-fails-to-recover-after-signal-loss.2474315/)

### Tertiary (LOW confidence)
- [DEV Community — iOS 26 BGContinuedProcessingTask overview](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5) — useful overview but needs validation against SDK
- [Medium — Why iOS Background Tasks Are Less Reliable](https://medium.com/@bhumibhuva18/why-ios-background-tasks-are-becoming-less-reliable-each-year-1514c72b406f) — corroborates documented behavior; anecdotal

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*
