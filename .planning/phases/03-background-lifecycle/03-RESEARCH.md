# Phase 3: Background Lifecycle - Research

**Researched:** 2026-03-25
**Domain:** iOS background execution, CoreLocation significant location changes, BGTaskScheduler, monitoring health detection
**Confidence:** HIGH

## Summary

Phase 3 transforms CellGuard from a foreground-only monitoring app into a persistent background service that survives iOS termination and device reboots. The primary background keep-alive mechanism is CLLocationManager's significant location change monitoring, which is the only Apple-sanctioned way to get indefinite background execution on a free personal team signing. BGAppRefreshTask provides supplementary wake events. The phase also adds monitoring health detection (Low Power Mode, Background App Refresh disabled, location authorization changes) and provisioning profile expiration tracking.

The existing ConnectivityMonitor already has the `updateLocation()` hook and probe timer management designed for Phase 3 integration. The key architectural work is: (1) a new LocationService that owns CLLocationManager + CLServiceSession, (2) an AppDelegate adaptor to handle location-based relaunches, (3) a MonitoringHealthService that aggregates system conditions into a health status, and (4) gap detection logic that records when the app was suspended/terminated.

**Primary recommendation:** Build a LocationService as an `@Observable` class owning CLLocationManager and CLServiceSession. Use `@UIApplicationDelegateAdaptor` to detect location-based relaunches and immediately restart monitoring. Store last-active timestamps in UserDefaults (not SwiftData) for fast gap detection on wake.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BKG-01 | Significant location change monitoring via CLLocationManager | LocationService pattern with CLLocationManager delegate, `startMonitoringSignificantLocationChanges()`, "Location updates" background mode |
| BKG-02 | Retain active CLServiceSession for iOS 18+ background delivery | CLServiceSession lifecycle management, must be held for entire monitoring duration |
| BKG-03 | BGAppRefreshTask for supplementary background wake | BGTaskScheduler registration in AppDelegate, task identifier in Info.plist, schedule-on-completion pattern |
| BKG-04 | Detect and warn about degraded monitoring conditions | ProcessInfo.isLowPowerModeEnabled, UIApplication.backgroundRefreshStatus, CLLocationManager.authorizationStatus checks |
| BKG-05 | 24+ hour background execution without watchdog termination | Significant location changes as primary keep-alive, no continuous GPS, minimal work per wake |
| DAT-03 | Persist monitoring state across kills/reboots, auto-resume | UserDefaults flag for monitoring-enabled, AppDelegate location launch detection, re-init monitoring on launch |
| DAT-05 | Track and record monitoring gaps | Compare last-active timestamp to current time on each wake, log gap events to SwiftData |
</phase_requirements>

## Standard Stack

### Core (Phase 3 additions)

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| CoreLocation (`CLLocationManager`) | iOS 2+ (stable) | Significant location changes + background wake | Only mechanism that relaunches a terminated app indefinitely. Battle-tested API. |
| `CLServiceSession` | iOS 18+ | Background location delivery authorization | Required on iOS 18+ to ensure location callbacks are delivered. Without it, background delivery silently stops. |
| `BGTaskScheduler` / `BGAppRefreshTask` | iOS 13+ | Supplementary background wake | System-discretionary but provides additional probe opportunities between location wakes. |
| `ProcessInfo` | iOS 9+ | Low Power Mode detection | `isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` notification |
| `UNUserNotificationCenter` | iOS 10+ | Provisioning profile expiry notification | Standard local notification API for the 48-hour warning |
| `UserDefaults` | iOS 2+ | Monitoring state persistence + gap detection timestamps | Fast read/write at launch, no SwiftData boot delay |

### Supporting

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| `@UIApplicationDelegateAdaptor` | iOS 14+ | Location-based relaunch detection | SwiftUI apps need AppDelegate for `didFinishLaunchingWithOptions` location key |
| `UNTimeIntervalNotificationTrigger` | iOS 10+ | Schedule profile expiry notification | 48 hours before expiration date |
| `PropertyListDecoder` | iOS 2+ | Parse embedded.mobileprovision | Read provisioning profile expiration date at app launch |

## Architecture Patterns

### New Services to Create

```
CellGuard/
  Services/
    ConnectivityMonitor.swift    # (existing) -- add runSingleProbe() public method
    EventStore.swift             # (existing) -- add insertGapEvent() method
    LocationService.swift        # NEW: CLLocationManager + CLServiceSession
    MonitoringHealthService.swift # NEW: aggregates health conditions
    ProvisioningProfileService.swift # NEW: reads expiration, schedules notification
  Models/
    ConnectivityEvent.swift      # (existing) -- add .monitoringGap event type
  App/
    AppDelegate.swift            # NEW: handles location-based relaunch
    CellGuardApp.swift           # (existing) -- add @UIApplicationDelegateAdaptor
```

### Pattern 1: Location-Based Relaunch Flow

**What:** When iOS terminates the app and a significant location change occurs, iOS relaunches the app into the background. The app must detect this, restart monitoring, run a probe, and return to suspended state.

**When to use:** Every app launch (check if it was a location-triggered relaunch).

**Flow:**
```
App terminated by iOS
  -> Significant location change detected by OS
  -> iOS relaunches app into background
  -> AppDelegate.didFinishLaunchingWithOptions receives .location key
  -> AppDelegate sets flag / initializes LocationService
  -> CellGuardApp.init() checks UserDefaults for monitoringEnabled
  -> If enabled: creates LocationService, starts monitoring, runs probe
  -> App processes location update, logs gap event if applicable
  -> App returns to suspended state until next wake
```

**Example:**
```swift
// AppDelegate.swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register BGTaskScheduler identifiers
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.cellguard.refresh",
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        // Detect location-based relaunch
        if launchOptions?[.location] != nil {
            // App was relaunched for a location event.
            // Monitoring will be started by CellGuardApp.init() if monitoringEnabled is true.
            UserDefaults.standard.set(true, forKey: "launchedForLocation")
        }

        return true
    }
}

// CellGuardApp.swift
@main
struct CellGuardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ... rest of init
}
```

### Pattern 2: Wake-Then-Probe

**What:** On each background wake (location or BGAppRefresh), immediately run a single HEAD probe and log the result, then schedule the next BGAppRefreshTask.

**When to use:** Every background wake event.

**Example:**
```swift
// LocationService -- on significant location change callback
func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }

    // Update ConnectivityMonitor with new location
    monitor.updateLocation(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        accuracy: location.horizontalAccuracy
    )

    // Detect and log any monitoring gap
    detectAndLogGap()

    // Run a single probe while we have background execution time
    Task { await monitor.runSingleProbe() }

    // Record last-active timestamp
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastActiveTimestamp")
}
```

### Pattern 3: Gap Detection via Timestamps

**What:** Store a `lastActiveTimestamp` in UserDefaults on every wake event. On next wake, compare the gap to expected maximum interval. If gap exceeds threshold (e.g., 10 minutes), log a `.monitoringGap` event.

**When to use:** Every wake event (location change, BGAppRefresh, foreground return).

**Example:**
```swift
func detectAndLogGap() {
    let now = Date()
    let lastActive = UserDefaults.standard.double(forKey: "lastActiveTimestamp")
    guard lastActive > 0 else {
        // First launch, no gap to detect
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastActiveTimestamp")
        return
    }

    let gapSeconds = now.timeIntervalSince1970 - lastActive
    let gapThreshold: TimeInterval = 600 // 10 minutes

    if gapSeconds > gapThreshold {
        // Log a monitoring gap event
        let gapEvent = ConnectivityEvent(
            eventType: .monitoringGap,
            pathStatus: .unsatisfied, // unknown during gap
            interfaceType: .unknown,
            // ... store gapDuration in dropDurationSeconds field or add new field
        )
        Task { try? await eventStore.insertEvent(gapEvent) }
    }

    UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastActiveTimestamp")
}
```

### Pattern 4: Monitoring Health Aggregation

**What:** A service that observes multiple system conditions and exposes a single `MonitoringHealth` enum: `.active`, `.degraded(reasons:)`, `.paused`.

**When to use:** UI binding for the health indicator.

**Example:**
```swift
@Observable
final class MonitoringHealthService {
    enum Health: Equatable {
        case active
        case degraded(reasons: [DegradedReason])
        case paused
    }

    enum DegradedReason: String {
        case lowPowerMode = "Low Power Mode is active"
        case backgroundRefreshDisabled = "Background App Refresh is disabled"
        case locationWhenInUse = "Location set to 'While Using' — background monitoring limited"
        case locationDenied = "Location access denied"
    }

    private(set) var health: Health = .active

    func evaluate(
        isMonitoring: Bool,
        locationAuth: CLAuthorizationStatus,
        backgroundRefresh: UIBackgroundRefreshStatus
    ) {
        guard isMonitoring else { health = .paused; return }

        var reasons: [DegradedReason] = []
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            reasons.append(.lowPowerMode)
        }
        if backgroundRefresh != .available {
            reasons.append(.backgroundRefreshDisabled)
        }
        if locationAuth == .authorizedWhenInUse {
            reasons.append(.locationWhenInUse)
        }
        if locationAuth == .denied || locationAuth == .restricted {
            reasons.append(.locationDenied)
        }

        health = reasons.isEmpty ? .active : .degraded(reasons: reasons)
    }
}
```

### Pattern 5: Provisioning Profile Expiration Detection

**What:** Read the embedded.mobileprovision file at app launch, parse the ExpirationDate, display it in the UI, and schedule a local notification 48 hours before expiry.

**Example:**
```swift
struct ProvisioningProfile: Decodable {
    let name: String
    let expirationDate: Date
    let creationDate: Date

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case expirationDate = "ExpirationDate"
        case creationDate = "CreationDate"
    }

    static func read() -> ProvisioningProfile? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dataString = String(data: data, encoding: .ascii) else {
            return nil
        }

        // Extract plist XML from the binary provisioning profile
        guard let plistStart = dataString.range(of: "<?xml"),
              let plistEnd = dataString.range(of: "</plist>") else {
            return nil
        }

        let plistString = String(dataString[plistStart.lowerBound...plistEnd.upperBound])
        guard let plistData = plistString.data(using: .utf8) else { return nil }

        let decoder = PropertyListDecoder()
        return try? decoder.decode(ProvisioningProfile.self, from: plistData)
    }
}
```

### Anti-Patterns to Avoid

- **Using Timer/DispatchSourceTimer for background probes:** iOS suspends timers when the app is backgrounded. They do NOT fire. Use the wake-then-probe pattern instead.
- **Creating a new NWPathMonitor on every wake:** NWPathMonitor should be created once and kept alive. The current ConnectivityMonitor creates it in init, which is correct. If the app is relaunched, a new ConnectivityMonitor instance is created naturally.
- **Storing gap detection timestamps in SwiftData:** SwiftData takes time to boot the container. UserDefaults is available immediately at launch, which is critical for fast gap detection before the app may be suspended again.
- **Requesting high-accuracy location:** Significant location changes already uses cell tower triangulation (~500m accuracy). Requesting high accuracy would drain battery and defeat the purpose.
- **Using `lazy var` with `@Observable`:** Already learned in Phase 2 -- use closure-initialized `let` instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Background wake scheduling | Custom timer/watchdog | CLLocationManager significant changes + BGAppRefreshTask | iOS kills custom timers; only Apple's mechanisms survive suspension |
| Low Power Mode detection | Polling ProcessInfo | `NSProcessInfoPowerStateDidChange` notification | Real-time, zero cost when not firing |
| Background refresh status | Polling UIApplication | `UIApplication.backgroundRefreshStatusDidChangeNotification` | Same -- observe, don't poll |
| Provisioning profile parsing | Manual string scanning | PropertyListDecoder with Decodable struct | Type-safe, handles date parsing automatically |
| Local notification scheduling | Manual date math | UNCalendarNotificationTrigger or UNTimeIntervalNotificationTrigger | Handles timezone, DND, notification settings automatically |

## Common Pitfalls

### Pitfall 1: Background App Refresh disabled prevents ALL background relaunches
**What goes wrong:** If the user disables Background App Refresh (globally or per-app), iOS will NOT relaunch the app for significant location changes, region monitoring, or any background event.
**Why it happens:** Apple documentation explicitly states this. Many developers miss this because significant location changes seem like a system-level service.
**How to avoid:** Check `UIApplication.shared.backgroundRefreshStatus` at launch and on `.backgroundRefreshStatusDidChangeNotification`. Warn the user prominently if `.denied`.
**Warning signs:** App stops getting background wakes despite location authorization being "Always".

### Pitfall 2: CLServiceSession must be retained for the entire monitoring lifetime
**What goes wrong:** If CLServiceSession is created as a local variable or released too early, background location delivery silently stops on iOS 18+.
**Why it happens:** CLServiceSession is a declarative session -- Core Location uses its existence to determine authorization intent.
**How to avoid:** Store CLServiceSession as a strong property on the LocationService. Create it when monitoring starts, nil it when monitoring stops. Never recreate it in a tight loop.
**Warning signs:** Location callbacks stop arriving in background but work fine in foreground.

### Pitfall 3: SwiftUI apps need AppDelegate for location-based relaunch detection
**What goes wrong:** Without an AppDelegate, there is no way to check `launchOptions[.location]` in a pure SwiftUI lifecycle.
**Why it happens:** SwiftUI's `@main App` struct does not receive launch options. The `@UIApplicationDelegateAdaptor` bridges this gap.
**How to avoid:** Add `@UIApplicationDelegateAdaptor(AppDelegate.self)` to the App struct. Implement `didFinishLaunchingWithOptions` in AppDelegate. Register BGTaskScheduler there too.
**Warning signs:** App never resumes monitoring after iOS kills it.

### Pitfall 4: BGAppRefreshTask has only ~30 seconds of execution time
**What goes wrong:** If you try to do too much work (multiple network requests, heavy SwiftData queries) in a BGAppRefreshTask, iOS kills the task before completion.
**Why it happens:** BGAppRefreshTask is designed for lightweight work. Heavy processing requires BGProcessingTask.
**How to avoid:** In the refresh handler: run ONE probe, log ONE gap event, schedule the next refresh. That's it. Keep total work under 10 seconds.
**Warning signs:** `task.expirationHandler` fires, task marked incomplete.

### Pitfall 5: NWPathMonitor initial callback race on relaunch
**What goes wrong:** When the app is relaunched from terminated state, ConnectivityMonitor creates a new NWPathMonitor which fires an initial callback. If gap detection runs before this callback, the path state is stale.
**Why it happens:** NWPathMonitor's first callback is asynchronous and reports current state.
**How to avoid:** The existing ConnectivityMonitor already handles this with `isInitialUpdate` flag. Ensure gap detection and probe run AFTER the initial path update is received, or accept that the first probe after relaunch uses potentially stale path state (acceptable for a diagnostic tool).
**Warning signs:** First event after relaunch has incorrect path status.

### Pitfall 6: embedded.mobileprovision not present in Simulator
**What goes wrong:** `Bundle.main.path(forResource: "embedded", ofType: "mobileprovision")` returns nil on Simulator.
**Why it happens:** Simulator builds are not signed with provisioning profiles.
**How to avoid:** Guard for nil return and show "Unknown (Simulator)" in the UI. Only schedule notifications when a real date is available.
**Warning signs:** Crash or nil unwrap in development.

### Pitfall 7: Must re-call startMonitoringSignificantLocationChanges on relaunch
**What goes wrong:** After iOS relaunches the app for a location event, you must create a new CLLocationManager and call `startMonitoringSignificantLocationChanges()` again, or you won't receive subsequent updates.
**Why it happens:** The previous CLLocationManager instance was destroyed when the app was terminated. Location monitoring registration does not persist across process death -- only the system's awareness that your app wants location events persists.
**How to avoid:** In CellGuardApp.init(), if UserDefaults says monitoring is enabled, always create LocationService and call start. Don't rely on "it was already started."
**Warning signs:** App gets ONE location callback after relaunch, then goes silent.

## Code Examples

### Info.plist Additions Required

```xml
<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>

<!-- Location Usage Descriptions -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>CellGuard needs Always location access to monitor cellular connectivity in the background using significant location changes. Location data stays on your device.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>CellGuard uses your location to correlate connectivity drops with geographic areas. Location data stays on your device.</string>

<!-- BGTaskScheduler Permitted Identifiers -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.cellguard.refresh</string>
</array>
```

### BGAppRefreshTask Registration and Scheduling

```swift
// In AppDelegate.didFinishLaunchingWithOptions:
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.cellguard.refresh",
    using: nil
) { task in
    guard let refreshTask = task as? BGAppRefreshTask else { return }
    // Run probe, detect gap, schedule next
    Task {
        await self.handleRefresh(refreshTask)
    }
}

// Schedule (call after each completed task AND on backgrounding)
func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.cellguard.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        print("Could not schedule app refresh: \(error)")
    }
}
```

### CLLocationManager Delegate Setup

```swift
// LocationService.swift
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var serviceSession: CLServiceSession?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func startMonitoring() {
        // Create and retain CLServiceSession for iOS 18+ background delivery
        serviceSession = CLServiceSession(authorization: .always)

        // Request Always authorization
        locationManager.requestAlwaysAuthorization()

        // Start significant location changes
        locationManager.startMonitoringSignificantLocationChanges()

        // Persist monitoring state
        UserDefaults.standard.set(true, forKey: "monitoringEnabled")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastActiveTimestamp")
    }

    func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        serviceSession = nil
        UserDefaults.standard.set(false, forKey: "monitoringEnabled")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Called on background wake from significant location change
        // ... update monitor location, run probe, detect gap
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
```

### ConnectivityEvent Model Addition

```swift
// Add to EventType enum:
case monitoringGap = 5  // Explicit raw value, never change existing values

// Update displayName:
case .monitoringGap: "Monitoring Gap"
```

### Local Notification for Profile Expiry

```swift
func scheduleExpiryNotification(expirationDate: Date) {
    let center = UNUserNotificationCenter.current()

    // Remove any existing notification
    center.removePendingNotificationRequests(withIdentifiers: ["profileExpiry"])

    // Schedule 48 hours before expiry
    let warningDate = expirationDate.addingTimeInterval(-48 * 3600)
    guard warningDate > Date() else { return } // Already past warning window

    let content = UNMutableNotificationContent()
    content.title = "CellGuard Profile Expiring"
    content.body = "Your provisioning profile expires in 48 hours. Re-sign the app in Xcode to continue monitoring."
    content.sound = .default

    let triggerInterval = warningDate.timeIntervalSinceNow
    let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: max(triggerInterval, 1),
        repeats: false
    )

    let request = UNNotificationRequest(
        identifier: "profileExpiry",
        content: content,
        trigger: trigger
    )

    center.add(request)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CLLocationManager only | CLLocationManager + CLServiceSession | iOS 18 (2024) | Must retain CLServiceSession or background delivery stops silently |
| AppDelegate lifecycle | SwiftUI `@main App` + `@UIApplicationDelegateAdaptor` | iOS 14 (2020) | Need adaptor for launch options; pure SwiftUI cannot detect location relaunch |
| `ObservableObject` / `@Published` | `@Observable` (Observation framework) | iOS 17 (2023) | More efficient, simpler syntax. Already adopted in Phase 2. |
| Manual BGTask scheduling | Same (no SwiftUI wrapper exists) | N/A | Must use UIKit-era BGTaskScheduler API; no SwiftUI equivalent |

## Open Questions

1. **CLServiceSession + Significant Location Changes interaction on iOS 26**
   - What we know: CLServiceSession is required for background location delivery on iOS 18+. Significant location changes pre-date this API by over a decade.
   - What's unclear: Whether CLServiceSession is strictly necessary for significant location changes (which are a lower-level service than continuous location updates), or only for CLLocationUpdate.liveUpdates / CLMonitor.
   - Recommendation: Create and retain CLServiceSession defensively. It cannot hurt and the cost is zero. Test on physical device.

2. **BGAppRefreshTask practical frequency on iOS 26**
   - What we know: Apple says system-discretionary, could be 15 minutes to hours.
   - What's unclear: Actual frequency on iPhone 17 Pro Max running iOS 26 for an app the user opens daily.
   - Recommendation: Treat as supplementary. Log when refresh tasks actually fire to understand real-world frequency.

3. **UserDefaults vs. SwiftData for monitoring state**
   - What we know: UserDefaults is available immediately at launch. SwiftData needs ModelContainer initialization.
   - What's unclear: Whether SwiftData container init completes fast enough for background launch scenarios.
   - Recommendation: Use UserDefaults for critical fast-path state (monitoringEnabled, lastActiveTimestamp). Use SwiftData only for event logging (which can be async).

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation - startMonitoringSignificantLocationChanges](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()) - Relaunch behavior, 500m threshold, Always authorization required
- [Apple Developer Documentation - Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background) - Background modes, UIBackgroundModes configuration
- [Apple Developer Documentation - BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler) - Task registration, scheduling API
- [Apple Developer Documentation - UIApplication.backgroundRefreshStatus](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus) - Background refresh detection
- [Apple Developer Documentation - isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/nsprocessinfo/1617047-lowpowermodeenabled) - Low Power Mode detection
- [Apple Developer Documentation - UIApplicationDelegateAdaptor](https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor) - SwiftUI AppDelegate bridge
- [Apple Developer Documentation - Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) - Local notification API

### Secondary (MEDIUM confidence)
- [Core Location Modern API Tips - twocentstudios.com](https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/) - CLServiceSession lifecycle, background delivery, iOS 18 requirements
- [Reading iOS Provisioning Profile in Swift - process-one.net](https://www.process-one.net/blog/reading-ios-provisioning-profile-in-swift/) - MobileProvision parsing pattern
- [Background Tasks in SwiftUI - swiftwithmajid.com](https://swiftwithmajid.com/2022/07/06/background-tasks-in-swiftui/) - BGTaskScheduler SwiftUI integration
- [Hacking with Swift - Low Power Mode detection](https://www.hackingwithswift.com/example-code/system/how-to-detect-low-power-mode-is-enabled) - ProcessInfo usage

### Tertiary (LOW confidence)
- [Understanding Significant Location in iOS - Medium](https://medium.com/swiftfy/understanding-significant-location-in-ios-a-developers-guide-463162753a10) - Community guide, claims verified against Apple docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All technologies are first-party Apple frameworks with stable APIs
- Architecture: HIGH - Patterns follow Apple's documented approaches for background location + BGTask
- Pitfalls: HIGH - Background App Refresh disabling location relaunches is documented by Apple; CLServiceSession requirement verified via twocentstudios.com (an authoritative iOS blog)
- Provisioning profile parsing: MEDIUM - Works on device, untested on iOS 26 specifically

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (30 days -- stable APIs, no expected changes)
