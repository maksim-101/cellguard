# Pitfalls Research

**Domain:** iOS background cellular connectivity monitoring app
**Researched:** 2026-03-25
**Confidence:** HIGH (core iOS background execution behavior is well-documented and stable)

## Critical Pitfalls

### Pitfall 1: NWPathMonitor Does Not Run When App Is Suspended

**What goes wrong:**
Developers assume NWPathMonitor will continue delivering path change callbacks while the app is in the background. It does not. Once iOS suspends the app (typically within seconds of backgrounding), NWPathMonitor stops firing. The app receives no network change notifications until it is brought back to the foreground or woken by another mechanism. This means the core monitoring strategy -- listening to NWPathMonitor for drops -- will miss every single drop that occurs while the app is suspended.

**Why it happens:**
NWPathMonitor is an in-process observer. It runs on a dispatch queue within your app's process. When iOS suspends the process, all queues stop, and no callbacks fire. There is no "background delivery" mode for NWPathMonitor the way there is for CoreLocation significant changes.

**How to avoid:**
NWPathMonitor is only useful for real-time status when the app is actively running (foreground or during a brief background execution window). The app must rely on a different mechanism to stay alive in the background. The viable strategy is: use significant location changes (CLLocationManager.startMonitoringSignificantLocationChanges) as the background wake trigger, then run a HEAD connectivity check each time the app is woken. NWPathMonitor supplements this by providing immediate feedback during foreground use and during the brief execution windows after wake events.

**Warning signs:**
- Testing only in the foreground and believing monitoring is working
- Log files showing zero events during overnight periods despite known drops
- NWPathMonitor handler fires with stale/duplicate status on foreground resume

**Phase to address:**
Phase 1 (Core Infrastructure) -- the background execution architecture must be designed correctly from the start. Retrofitting is expensive.

---

### Pitfall 2: Periodic 60-Second HEAD Requests Are Impossible in Background

**What goes wrong:**
The project spec calls for HEAD requests to Apple's captive portal every 60 seconds. iOS provides no mechanism for guaranteed periodic execution at sub-minute intervals in the background. Background App Refresh (BGAppRefreshTaskRequest) gives roughly 30 seconds of execution time, scheduled at the system's discretion (typically every 15+ minutes, sometimes hours). There is no Timer, DispatchSourceTimer, or RunLoop that survives app suspension.

**Why it happens:**
iOS aggressively suspends apps to preserve battery. There is no general-purpose mechanism for running code periodically at a guaranteed interval in the background. This is a deliberate platform constraint, not a bug.

**How to avoid:**
Accept that background connectivity checks will be event-driven, not periodic:
1. **Significant location changes** wake the app (every ~500m of movement or cellular tower change). On wake, perform a HEAD check.
2. **BGAppRefreshTask** provides infrequent supplementary wake events (system-scheduled, not reliable for timing).
3. **In the foreground**, the 60-second Timer works perfectly -- use it there.
4. **Combine approaches**: log the "last checked" timestamp with each event so gaps in monitoring are visible in the exported data.

The effective monitoring interval in background will be irregular (minutes to hours), not 60 seconds. The exported data should reflect this honestly rather than pretending continuous monitoring occurred.

**Warning signs:**
- Timer-based code that works in foreground but produces no events in background
- Attempting to use `beginBackgroundTask` in a loop (gives ~30 seconds total, not repeating)
- Looking for "background timer" libraries (they all hit the same iOS wall)

**Phase to address:**
Phase 1 (Core Infrastructure) -- the monitoring cadence must be architecturally sound before building features on top of it.

---

### Pitfall 3: NWPathMonitor Reports "Satisfied" During Silent Modem Failures

**What goes wrong:**
The specific bug CellGuard is designed to detect -- the "attached but unreachable" baseband failure -- will NOT be caught by NWPathMonitor alone. NWPathMonitor reports the network path as `.satisfied` because the device still has a cellular interface that appears connected. The modem thinks it is registered on the network. Data simply does not transit. This is the exact failure mode documented in PROJECT.md ("callers hear ringing, SMS show delivered, but nothing reaches the device").

**Why it happens:**
NWPathMonitor checks whether a network interface exists and appears connected at the link layer. It does not perform end-to-end connectivity verification. A modem stuck in a broken state-machine position still presents a valid cellular interface to the Network framework.

**How to avoid:**
The HEAD request to `apple.com/library/test/success.html` is the only reliable detection mechanism for this failure. Every wake event (significant location change, BGAppRefreshTask, foreground timer) must perform an active HTTP check, not just read NWPathMonitor status. The logic should be:
- NWPathMonitor says `.unsatisfied` -> definite drop, log immediately
- NWPathMonitor says `.satisfied` -> perform HEAD request to verify
- HEAD request fails while path is "satisfied" -> this is the silent modem failure, log as critical event

**Warning signs:**
- Trusting NWPathMonitor `.satisfied` status without active verification
- Test logs that never show "silent failure" events despite user experiencing drops
- Missing the distinction between "interface exists" and "data transits"

**Phase to address:**
Phase 1 (Core Infrastructure) -- this is the central detection algorithm and must be correct from day one.

---

### Pitfall 4: Significant Location Changes Stop Working Silently

**What goes wrong:**
The app registers for significant location changes as its primary background wake mechanism, and it works during testing. Then it silently stops working. The app is never woken again and misses all drops. There are multiple causes:
1. **User disables Background App Refresh** (globally or per-app) -- significant location changes will NOT relaunch a terminated app when BAR is off. The app receives no events, even in the foreground.
2. **User force-quits the app** from the app switcher -- iOS will not relaunch the app for significant location changes after a force quit (iOS 15+ behavior).
3. **Low Power Mode** -- disables Background App Refresh, which cascades to disable significant location change relaunch.
4. **iOS deprioritizes the app** -- if the user has not actively used the app recently, iOS's predictive engine may reduce or halt background execution.

**Why it happens:**
Apple has progressively tightened background execution since iOS 15. The documented guarantee that "significant location changes relaunch terminated apps" has become conditional on several user-controlled settings and system heuristics that are not well-documented.

**How to avoid:**
1. Add a prominent in-app notice explaining that Background App Refresh MUST be enabled and the app must NOT be force-quit from the app switcher.
2. On each foreground launch, check `UIApplication.shared.backgroundRefreshStatus` and warn the user if it is `.denied` or `.restricted`.
3. Check `ProcessInfo.processInfo.isLowPowerModeEnabled` and warn that monitoring may be degraded.
4. Log the app's launch reason (from `application(_:didFinishLaunchingWithOptions:)` launch options) to track whether background wakes are actually occurring.
5. Store a "last background wake" timestamp and display staleness warnings in the UI.

**Warning signs:**
- Monitoring works during development but fails in real-world use
- Log files show no events between user sessions
- App only logs events when user opens it (foreground-only operation)

**Phase to address:**
Phase 1 (Core Infrastructure) for the monitoring architecture; Phase 2 (UI/Dashboard) for user-facing warnings about required settings.

---

### Pitfall 5: 7-Day Free Provisioning Expiration Kills Background Monitoring

**What goes wrong:**
With free personal team signing, the provisioning profile expires every 7 days. When it expires, the app crashes on launch. If the user does not notice and re-deploy within 7 days, there is a gap in monitoring data with no indication of why. Worse: if the app was collecting evidence for an Apple Feedback Assistant report, the gap undermines the data's credibility.

**Why it happens:**
Free provisioning profiles are deliberately limited by Apple to 7-day validity. There is no workaround on the free tier. The app binary on the device simply stops being valid.

**How to avoid:**
1. Build a re-deployment reminder system: use iOS local notifications to remind yourself to re-deploy 1-2 days before expiration.
2. Record the provisioning profile expiration date at build time (embed it in the app bundle or Info.plist via a build script) and display a countdown in the UI.
3. On each app launch, check if remaining validity is < 2 days and show a prominent warning.
4. Document the re-deployment procedure clearly so it becomes a 2-minute routine.
5. Consider upgrading to paid Apple Developer Program ($99/year) if the 7-day cycle becomes burdensome -- this is the real fix.

**Warning signs:**
- Gaps in monitoring data at ~7 day intervals
- App stops launching with no error message (just crashes)
- Forgetting to re-deploy during busy weeks

**Phase to address:**
Phase 1 (Core Infrastructure) for build-time expiration embedding; Phase 2 (UI) for expiration warnings and local notification reminders.

---

### Pitfall 6: CTCarrier Deprecation and CoreTelephony API Fragility

**What goes wrong:**
The app uses CTTelephonyNetworkInfo to capture radio access technology (LTE/5G/3G) and carrier name per event. CTCarrier was deprecated in iOS 16. The remaining APIs (serviceCurrentRadioAccessTechnology, serviceSubscriberCellularProviders) still work but return limited data. Apple has been systematically reducing what CoreTelephony exposes to third-party apps, and there is no replacement framework announced.

**Why it happens:**
Apple considers carrier and radio details to be privacy-sensitive and has been deprecating exposure over multiple iOS versions. There is no public API for signal strength (dBm/RSSI), which is already correctly scoped out of the project.

**How to avoid:**
1. Use `serviceCurrentRadioAccessTechnology` (not the deprecated singular version) and `serviceSubscriberCellularProviders` while they still work.
2. Wrap all CoreTelephony calls in a helper that returns Optional values, gracefully handling nil/empty responses.
3. Store the raw radio technology string (e.g., `CTRadioAccessTechnologyLTE`) rather than mapping to enums, so new values from future iOS versions are captured without code changes.
4. Do not depend on carrier name for critical logic -- it may return empty strings on some configurations.
5. Accept that this data is "best effort" supplementary metadata, not guaranteed.

**Warning signs:**
- Compiler warnings about deprecated APIs during build
- Empty carrier name strings in logged events
- Radio technology returning nil despite active cellular connection

**Phase to address:**
Phase 1 (Core Infrastructure) -- wrap these APIs defensively from the start.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using UserDefaults for event storage | Quick to implement | Cannot query, no indexing, slow with thousands of events, no migration path | Never -- use SwiftData/SQLite from day one |
| Skipping structured error handling for HEAD requests | Faster initial development | Cannot distinguish timeout vs DNS failure vs connection refused -- all critical diagnostic signals | Never -- error categorization is core to the app's purpose |
| Hardcoding Apple captive portal URL | One less config value | URL could change; no fallback if Apple rate-limits or blocks | MVP only -- make configurable early |
| Testing only in foreground | Faster iteration | Background behavior is fundamentally different and untestable from foreground observations | Never for monitoring features |
| Storing timestamps as formatted strings | Readable in logs | Cannot compute durations, sort, or filter by time range | Never -- store as Date/TimeInterval, format on display |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Apple captive portal (HEAD request) | Using GET instead of HEAD, not setting short timeouts | Use HEAD method, 10-second timeout, check for HTTP 200 response specifically (Apple returns `<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>`) |
| CLLocationManager significant changes | Not calling `startMonitoringSignificantLocationChanges()` early enough in app lifecycle | Call in `application(_:didFinishLaunchingWithOptions:)` so it is active even on background relaunch |
| NWPathMonitor | Starting monitor on main queue | Use a dedicated background DispatchQueue to avoid blocking UI; dispatch UI updates back to main queue |
| CTTelephonyNetworkInfo | Creating a new instance per query | Create one shared instance at app launch and keep it alive -- re-creation can miss state |
| BGAppRefreshTaskRequest | Not registering task identifier in Info.plist AND in code | Must register in both `BGTaskScheduler.register(forTaskWithIdentifier:)` during launch AND in Info.plist `BGTaskSchedulerPermittedIdentifiers` -- silent failure if either is missing |
| CoreLocation "Always" authorization | Requesting `.authorizedAlways` directly | Must request `.authorizedWhenInUse` first, then `.authorizedAlways` -- iOS requires the two-step flow since iOS 13 |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Unbounded event log growth | App launch slows, export takes minutes, SwiftData queries lag | Implement rolling window (keep 30 days, archive older) or pagination for UI display | ~10,000+ events (months of logging at moderate drop frequency) |
| HEAD requests on cellular with no timeout | Request hangs for 60+ seconds during modem failure, blocking the monitoring queue | Set `timeoutIntervalForRequest` to 10 seconds; treat timeout as connectivity failure | Every silent modem failure event |
| Logging location with every event using continuous GPS | Battery drain visible in Settings > Battery | Use significant location changes only (cellular tower-based, not GPS); store last-known location with events | Immediately -- continuous GPS in background is a battery killer |
| SwiftData writes on main thread | UI stutters when logging rapid succession of events | Use a background ModelContext for all writes; only read on main context | Rapid network flapping (multiple events per second) |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging precise GPS coordinates | Privacy risk if export file is shared beyond Apple Feedback Assistant | Log coarse location only (significant location changes give ~500m accuracy, which is appropriate) |
| Including device identifiers in export | Privacy leakage if file is shared publicly | Only include device model and iOS version, not UDID/serial/IMEI |
| Not sanitizing carrier/network data in exports | Could reveal SIM details to unintended recipients | Review export format -- carrier name is fine, but do not expose ICCID or phone number (which CoreTelephony does not provide anyway, but verify) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No indication that monitoring is degraded or stopped | User believes app is monitoring when it is not (BAR disabled, force-quit, expired profile) | Show persistent status indicator: green = actively monitoring, yellow = degraded (BAR off, Low Power Mode), red = stopped |
| Showing raw NWPath status strings | Meaningless to non-developer users | Translate to human-readable: "Cellular Connected", "No Signal", "Connected but Not Working (Silent Failure)" |
| Export produces a single massive CSV | Hard to attach to Feedback Assistant, hard to read | Offer date-range filtering for export; include summary statistics at top of file |
| Dashboard shows lifetime stats only | Cannot see "drops today" vs historical pattern | Default to 24-hour view with toggle for 7-day and 30-day |
| No onboarding for required permissions | User denies location or BAR, app silently fails to monitor | Step-by-step setup flow explaining WHY each permission is needed for monitoring to work |

## "Looks Done But Isn't" Checklist

- [ ] **Background monitoring:** Test by leaving phone in pocket for 4+ hours with app backgrounded -- verify events are logged (not just foreground testing)
- [ ] **Silent modem detection:** Verify the app distinguishes between "no cellular" (NWPathMonitor `.unsatisfied`) and "cellular present but broken" (path `.satisfied` + HEAD fails) -- these are different event types
- [ ] **App relaunch after termination:** Force-quit the app, move to a new cell tower area, verify the app relaunches and logs events
- [ ] **Low Power Mode behavior:** Enable Low Power Mode and verify monitoring still functions (it may not -- document the limitation)
- [ ] **Export completeness:** Export a CSV and verify every field is populated for every event -- watch for nil carrier names, missing locations, or zero durations
- [ ] **7-day expiration:** Actually let 7 days pass and verify the re-deployment process works smoothly and no data is lost
- [ ] **Rapid event handling:** Simulate network flapping (toggle airplane mode rapidly) and verify events are logged correctly without duplicates or crashes
- [ ] **Storage after weeks:** Load-test with thousands of synthetic events to verify UI performance does not degrade

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NWPathMonitor-only architecture (no active checks) | MEDIUM | Add HEAD request layer; refactor event detection to two-signal system (passive + active) |
| UserDefaults for storage | HIGH | Migrate all data to SwiftData/SQLite; write migration script; risk of data loss during migration |
| No background wake mechanism | HIGH | Add significant location changes, BGAppRefreshTask; requires re-architecture of monitoring loop |
| Missing event metadata (no timestamps/durations) | HIGH | Cannot retroactively add metadata to already-logged events; must restart data collection |
| Expired provisioning gap | LOW | Re-deploy app; monitoring data gap is permanent but app resumes normally |
| Battery drain from aggressive monitoring | MEDIUM | Reduce check frequency, remove continuous GPS, audit network usage; may require re-testing timing |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NWPathMonitor suspended in background | Phase 1: Core Infrastructure | Verify background events logged after 4+ hours |
| 60-second timer impossible in background | Phase 1: Core Infrastructure | Verify event-driven architecture produces logs in background |
| Satisfied path during silent failure | Phase 1: Core Infrastructure | Simulate silent failure (e.g., block DNS), verify HEAD check catches it |
| Significant location changes stop silently | Phase 1: Core Infrastructure + Phase 2: UI | Check BAR status on launch; display monitoring health indicator |
| 7-day provisioning expiration | Phase 1: Build Config + Phase 2: UI | Expiration date visible in UI; local notification fires 2 days before |
| CTCarrier deprecation | Phase 1: Core Infrastructure | All CoreTelephony calls wrapped with Optional handling; no crashes on nil |
| Unbounded storage growth | Phase 2: Data Management | Test with 10K+ events; verify query performance and export speed |
| No permission onboarding | Phase 2: UI/Dashboard | First-launch flow requests all permissions with explanations |

## Sources

- [NWPathMonitor Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [NWPathMonitor pathUpdateHandler background behavior -- Apple Developer Forums](https://developer.apple.com/forums/thread/662297)
- [NWPathMonitor non-functional report -- Apple Developer Forums](https://developer.apple.com/forums/thread/658516)
- [iOS Background Execution Limits -- Apple Developer Forums](https://developer.apple.com/forums/thread/685525)
- [Periodic iOS background execution -- Apple Developer Forums](https://developer.apple.com/forums/thread/724506)
- [Significant Location Change service and BAR dependency -- Apple Developer Forums](https://developer.apple.com/forums/thread/694081)
- [Background Location Update stops -- Apple Developer Forums](https://developer.apple.com/forums/thread/75072)
- [iOS 26 BGContinuedProcessingTask -- WWDC 2025](https://developer.apple.com/videos/play/wwdc2025/227/)
- [BGContinuedProcessingTask overview -- DEV Community](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)
- [Why iOS Background Tasks Are Less Reliable -- Medium](https://medium.com/@bhumibhuva18/why-ios-background-tasks-are-becoming-less-reliable-each-year-1514c72b406f)
- [Detecting Internet Access on iOS 12+ (NWPathMonitor limitations)](http://rwbutler.github.io/2018-12-26-detecting-internet-access-on-ios-12/)
- [Free Provisioning Profile Limitations -- Apple Developer Forums](https://developer.apple.com/forums/thread/669516)
- [CTTelephonyNetworkInfo Apple Developer Documentation](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo)
- [CTCarrier deprecation discussion -- Apple Developer Forums](https://developer.apple.com/forums/thread/751785)
- [Key Considerations Before Using SwiftData -- fatbobman.com](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [Energy Efficiency Guide for iOS Apps -- Apple Developer Archive](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/WorkLessInTheBackground.html)
- [Handling location updates in the background -- Apple Developer Documentation](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)

---
*Pitfalls research for: iOS background cellular connectivity monitoring*
*Researched: 2026-03-25*
