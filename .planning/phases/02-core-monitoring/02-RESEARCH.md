# Phase 2: Core Monitoring - Research

**Researched:** 2026-03-25
**Domain:** Network monitoring (NWPathMonitor), active connectivity probing (URLSession), cellular telemetry (CoreTelephony), event classification and correlation
**Confidence:** HIGH

## Summary

Phase 2 builds the detection engine on top of the Phase 1 data layer. There are three independent subsystems that must be coordinated: (1) NWPathMonitor for real-time path change detection, (2) a periodic HEAD probe for silent modem failure detection, and (3) CoreTelephony for radio access technology metadata. These are unified by a `ConnectivityMonitor` coordinator that classifies events, enriches them with metadata, calculates drop durations, and writes them through the existing `EventStore`.

The central architectural challenge is event classification logic -- translating raw NWPath transitions and probe results into the correct `EventType` values. A path going from satisfied-cellular to unsatisfied is an overt drop. A path remaining satisfied-cellular while a HEAD probe times out is a silent modem failure. A path going from cellular to wifi while satisfied means a fallback. The coordinator must track previous state to make these classifications and compute drop durations.

The secondary challenge is concurrency design. NWPathMonitor delivers callbacks on its assigned DispatchQueue. The HEAD probe uses async/await URLSession. CoreTelephony notifications arrive on arbitrary queues. The coordinator must serialize state access without blocking. Swift 6.2's Approachable Concurrency and the `@Observable` macro simplify this.

**Primary recommendation:** Build a single `ConnectivityMonitor` class (annotated `@Observable` for future UI binding) that owns the NWPathMonitor, Timer-based probe scheduler, and CTTelephonyNetworkInfo. It tracks previous path state for classification, uses the EventStore actor for persistence, and runs the probe timer only in the foreground (Timer is suspended by iOS in background -- background probing is Phase 3's concern).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MON-01 | Monitor network path changes in real-time via NWPathMonitor and log every transition | NWPathMonitor.pathUpdateHandler fires on every path change. Compare previous vs current NWPath to detect status and interface transitions. Map NWPath.Status to PathStatus enum, NWPath.usesInterfaceType() to InterfaceType enum. |
| MON-02 | Periodic active connectivity probe (HEAD request to Apple captive portal) to detect silent modem failures | URLSession.shared with default config, HEAD request to `https://captive.apple.com/hotspot-detect.html`, 10s timeout, 60s interval via Timer.scheduledTimer (foreground only). |
| MON-03 | Classify probe timeout while path "satisfied" as "silent modem failure" event type | Classification logic in coordinator: if pathStatus == .satisfied && interfaceType == .cellular && probe fails -> eventType = .silentFailure |
| MON-04 | Capture radio access technology (LTE, 5G NR, etc.) via CTTelephonyNetworkInfo | CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology returns [String: String] dictionary keyed by service identifier. Use `.values.first` for primary radio tech. String constants like CTRadioAccessTechnologyLTE, CTRadioAccessTechnologyNR. |
| MON-05 | Capture carrier metadata (carrier name, MCC/MNC) on best-effort basis | CTTelephonyNetworkInfo().serviceSubscriberCellularProviders is deprecated since iOS 16.4. May return nil on iOS 26. Store "Unknown" as fallback. Best-effort only. |
| MON-06 | Detect and log when device falls back to Wi-Fi after cellular drop | Compare previous interfaceType (.cellular) with current (.wifi) when path remains satisfied. Log as a distinct pathChange event with interfaceType = .wifi. Previous state tracking in coordinator enables this. |
| DAT-02 | Calculate and store drop duration (time from drop-start to next restoration) | Coordinator stores `dropStartDate: Date?` when a drop event occurs (path becomes unsatisfied or silent failure detected). On next `connectivityRestored` event, calculate `Date().timeIntervalSince(dropStartDate)` and store in `dropDurationSeconds`. |
| DAT-04 | Capture coarse location (via significant location changes) with each event | Phase 2 scope: accept optional latitude/longitude/accuracy parameters when creating events. The actual CLLocationManager significant location change setup is Phase 3 (BKG-01). For Phase 2, the coordinator accepts a "last known location" that gets attached to events. The location provider will be plugged in during Phase 3. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Network framework (`NWPathMonitor`) | iOS 12+ (stable, unchanged API) | Real-time network path monitoring | First-party. Fires callback on every path status change and interface change. No third-party wrapper needed -- API is simple. |
| Foundation (`URLSession`) | Built-in | Active HEAD probe for silent failure detection | Default URLSession config with `timeoutIntervalForRequest = 10`. URLSessionDataTask for HEAD requests. No background config needed -- probe runs from foreground/wake context only. |
| CoreTelephony (`CTTelephonyNetworkInfo`) | iOS 12+ | Radio access technology and carrier metadata | Only API for getting radio tech (LTE/5G/3G). `serviceCurrentRadioAccessTechnology` dict returns current radio per SIM service. Carrier name via deprecated `serviceSubscriberCellularProviders` on best-effort. |
| SwiftData (from Phase 1) | iOS 17+ | Event persistence | Already configured. EventStore @ModelActor accepts writes. |
| Swift 6.2 / Observation framework | Xcode 26 | Coordinator state management | `@Observable` macro for ConnectivityMonitor gives future UI phases live state binding with no additional work. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CoreLocation (`CLLocation`) | iOS 2+ | Location data type | Accept CLLocation from Phase 3's location provider. Extract latitude, longitude, horizontalAccuracy. |
| Foundation (`Timer`) | Built-in | 60-second probe scheduling (foreground) | Timer.scheduledTimer for foreground probe cadence. iOS suspends timers in background -- this is correct for Phase 2 (foreground only). Phase 3 adds background wake-then-probe. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Timer for probe scheduling | DispatchSourceTimer | Timer integrates with RunLoop naturally and is simpler. DispatchSourceTimer also suspended in background. No advantage. |
| NWPathMonitor.pathUpdateHandler | NWPathMonitor async sequence (for await) | AsyncSequence is cleaner syntax but harder to integrate with the coordinator's state tracking pattern. Callback is more explicit about state comparison. |
| URLSession HEAD to captive.apple.com | URLSession GET to any public URL | Apple's captive portal URL is purpose-built for connectivity checks. Lightweight, Apple-hosted, same URL iOS uses internally. |

## Architecture Patterns

### Recommended Project Structure (Phase 2 additions)
```
CellGuard/
├── CellGuardApp.swift              # Add ConnectivityMonitor initialization
├── Models/
│   └── ConnectivityEvent.swift     # No changes needed (Phase 1 complete)
├── Services/
│   ├── EventStore.swift            # No changes needed (Phase 1 complete)
│   └── ConnectivityMonitor.swift   # NEW: Main monitoring coordinator
├── Views/
│   └── ContentView.swift           # Minor: show monitoring status
└── Info.plist
```

### Pattern 1: ConnectivityMonitor Coordinator
**What:** A single `@Observable` class that owns all monitoring subsystems (NWPathMonitor, probe timer, CTTelephonyNetworkInfo), tracks previous state, classifies events, and writes through EventStore.
**When to use:** This is the single entry point for all monitoring logic in the app.
**Example:**
```swift
import Network
import CoreTelephony
import Observation
import Foundation

@Observable
final class ConnectivityMonitor {
    // Published state for UI binding (Phase 4)
    private(set) var isMonitoring = false
    private(set) var currentPathStatus: PathStatus = .unsatisfied
    private(set) var currentInterfaceType: InterfaceType = .unknown
    private(set) var currentRadioTechnology: String?

    // Internal state for classification
    private var previousPathStatus: PathStatus = .unsatisfied
    private var previousInterfaceType: InterfaceType = .unknown
    private var dropStartDate: Date?
    private var lastLocation: (latitude: Double, longitude: Double, accuracy: Double)?

    // Dependencies
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.cellguard.pathmonitor")
    private let networkInfo = CTTelephonyNetworkInfo()
    private var probeTimer: Timer?
    private let eventStore: EventStore

    // Configuration
    private let probeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!
    private let probeTimeout: TimeInterval = 10
    private let probeInterval: TimeInterval = 60

    init(eventStore: EventStore) {
        self.eventStore = eventStore
    }

    func startMonitoring() { /* ... */ }
    func stopMonitoring() { /* ... */ }
}
```

### Pattern 2: Path Change Classification
**What:** Compare previous NWPath state to current state to determine the correct EventType.
**When to use:** Every NWPathMonitor callback.
**Example:**
```swift
// Inside pathUpdateHandler callback:
private func handlePathUpdate(_ path: NWPath) {
    let newStatus = mapPathStatus(path.status)
    let newInterface = detectPrimaryInterface(path)

    // Case 1: Overt drop (was satisfied, now unsatisfied)
    if previousPathStatus == .satisfied && newStatus == .unsatisfied {
        dropStartDate = Date()
        logEvent(type: .pathChange, status: newStatus, interface: newInterface)
    }

    // Case 2: Connectivity restored
    else if previousPathStatus == .unsatisfied && newStatus == .satisfied {
        let duration = dropStartDate.map { Date().timeIntervalSince($0) }
        dropStartDate = nil
        logEvent(type: .connectivityRestored, status: newStatus,
                 interface: newInterface, dropDuration: duration)
    }

    // Case 3: Wi-Fi fallback (cellular -> wifi while still satisfied)
    else if previousInterfaceType == .cellular && newInterface == .wifi
            && newStatus == .satisfied {
        logEvent(type: .pathChange, status: newStatus, interface: newInterface)
    }

    // Case 4: Other path changes (interface change, flags change)
    else if newStatus != previousPathStatus || newInterface != previousInterfaceType {
        logEvent(type: .pathChange, status: newStatus, interface: newInterface)
    }

    previousPathStatus = newStatus
    previousInterfaceType = newInterface
}
```

### Pattern 3: Interface Type Detection from NWPath
**What:** Map NWPath's `usesInterfaceType()` method to the app's InterfaceType enum.
**When to use:** Every path update to determine the primary active interface.
**Example:**
```swift
private func detectPrimaryInterface(_ path: NWPath) -> InterfaceType {
    // Check in priority order (most specific first)
    if path.usesInterfaceType(.cellular) { return .cellular }
    if path.usesInterfaceType(.wifi) { return .wifi }
    if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
    if path.usesInterfaceType(.loopback) { return .loopback }
    if path.usesInterfaceType(.other) { return .other }
    return .unknown
}
```

### Pattern 4: HEAD Probe with Timeout
**What:** A URLSession HEAD request to Apple's captive portal endpoint with a 10-second timeout.
**When to use:** Every 60 seconds from the probe timer, and optionally on-demand after a path change.
**Example:**
```swift
private func runProbe() async {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = probeTimeout
    config.waitsForConnectivity = false  // We WANT immediate failure
    let session = URLSession(configuration: config)

    var request = URLRequest(url: probeURL)
    request.httpMethod = "HEAD"

    let start = Date()
    do {
        let (_, response) = try await session.data(for: request)
        let latencyMs = Date().timeIntervalSince(start) * 1000
        let httpResponse = response as? HTTPURLResponse

        if httpResponse?.statusCode == 200 {
            logEvent(type: .probeSuccess, probeLatencyMs: latencyMs)
        } else {
            logEvent(type: .probeFailure,
                     probeFailureReason: "HTTP \(httpResponse?.statusCode ?? 0)")
        }
    } catch {
        let latencyMs = Date().timeIntervalSince(start) * 1000

        // Silent modem failure: path says satisfied but probe fails
        if currentPathStatus == .satisfied && currentInterfaceType == .cellular {
            logEvent(type: .silentFailure,
                     probeLatencyMs: latencyMs,
                     probeFailureReason: error.localizedDescription)
            dropStartDate = dropStartDate ?? Date()  // Start tracking drop
        } else {
            logEvent(type: .probeFailure,
                     probeLatencyMs: latencyMs,
                     probeFailureReason: error.localizedDescription)
        }
    }
}
```

### Pattern 5: Radio Technology and Carrier Capture
**What:** Read current radio access technology and carrier name from CTTelephonyNetworkInfo at the moment of event creation.
**When to use:** Every event log call.
**Example:**
```swift
private func captureRadioTechnology() -> String? {
    // serviceCurrentRadioAccessTechnology returns [String: String]
    // keyed by service identifier (SIM slot). Use first value for primary.
    return networkInfo.serviceCurrentRadioAccessTechnology?.values.first
}

private func captureCarrierName() -> String? {
    // Deprecated since iOS 16.4 -- may return nil on iOS 26
    // Best-effort: return carrier name if available, nil otherwise
    return networkInfo.serviceSubscriberCellularProviders?.values.first?.carrierName
}
```

### Pattern 6: NWPath Status Mapping
**What:** Map NWPath.Status to the app's PathStatus enum.
**When to use:** Every path update.
**Example:**
```swift
private func mapPathStatus(_ status: NWPath.Status) -> PathStatus {
    switch status {
    case .satisfied: return .satisfied
    case .unsatisfied: return .unsatisfied
    case .requiresConnection: return .requiresConnection
    @unknown default: return .unsatisfied
    }
}
```

### Anti-Patterns to Avoid
- **Creating NWPathMonitor per check:** Create ONE monitor at init, start it once, stop it on deinit. Do not create/destroy repeatedly.
- **Using background URLSession config for probes:** Background URLSession is for large transfers. Use default config with short timeout for HEAD probes. Background sessions are managed by nsurlsessiond and do not give immediate results.
- **Running Timer in background:** iOS suspends Timer when app is backgrounded. Do not rely on Timer for background probe scheduling. Phase 2 is foreground-only; Phase 3 adds background wake-then-probe via significant location changes.
- **Blocking the NWPathMonitor queue:** The pathUpdateHandler runs on the monitor's DispatchQueue. Do not perform synchronous I/O or long operations in the callback. Dispatch classification logic to an async Task.
- **Ignoring NWPath.isExpensive / isConstrained:** These flags change independently of status. Capture them on every event for complete metadata.
- **Creating new URLSession per probe:** Reuse a single URLSession instance. Creating sessions is expensive.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Network reachability | Custom socket/ping monitoring | `NWPathMonitor` | First-party, handles all edge cases (VPN, proxy, constrained paths) |
| Connectivity verification | Custom TCP connection check | `URLSession` HEAD to `captive.apple.com` | Same endpoint iOS uses; lightweight; handles redirects/proxies correctly |
| Radio tech detection | Parsing carrier settings or private APIs | `CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology` | Only public API for radio tech. Returns standard string constants. |
| Periodic task scheduling | GCD timer / DispatchSourceTimer | `Timer.scheduledTimer` (foreground) | Simpler, RunLoop-integrated, auto-invalidated on deinit |
| State observation for UI | Custom delegate/notification pattern | `@Observable` macro | Native SwiftUI integration, efficient view updates |

**Key insight:** All three monitoring subsystems (path, probe, telemetry) have simple first-party APIs. The complexity is entirely in the classification logic and state coordination, not in the API usage.

## Common Pitfalls

### Pitfall 1: NWPathMonitor Fires Immediately on Start
**What goes wrong:** The first pathUpdateHandler callback fires immediately after `start(queue:)` with the current path state, not a transition. If the coordinator treats this as a "change," it logs a spurious event.
**Why it happens:** NWPathMonitor delivers the current state as the first callback, by design.
**How to avoid:** Set an `isInitialUpdate` flag. On the first callback, capture the initial state (previousPathStatus, previousInterfaceType) but do NOT log an event. Only log on subsequent callbacks that represent actual transitions.
**Warning signs:** A "path change" event logged at app launch with no actual network change.

### Pitfall 2: NWPath.usesInterfaceType Can Return True for Multiple Types
**What goes wrong:** `path.usesInterfaceType(.cellular)` and `path.usesInterfaceType(.wifi)` can BOTH return true simultaneously if both interfaces are available.
**Why it happens:** `usesInterfaceType` checks if the path MAY use that interface, not which one is currently active. iOS can use both wifi and cellular simultaneously (multipath).
**How to avoid:** Check in priority order (cellular first for this app's purpose -- we care about cellular drops). Also check `availableInterfaces` array, which is ordered by preference. The first element is the preferred interface.
**Warning signs:** Events logged with wrong interface type, or "cellular drop" not detected because wifi was also available.

### Pitfall 3: Timer Not Firing in Background
**What goes wrong:** The 60-second probe timer stops firing when the app enters background.
**Why it happens:** iOS suspends Timer (and DispatchSourceTimer) when the app is suspended. Timers are RunLoop-based and RunLoops are paused on suspension.
**How to avoid:** This is expected behavior for Phase 2. Do not try to work around it. Invalidate the timer on background entry, restart on foreground entry. Phase 3 adds background wake-then-probe via significant location changes.
**Warning signs:** No probe events logged while app is in background (this is correct behavior for Phase 2).

### Pitfall 4: CTCarrier Returning Nil on iOS 16.4+
**What goes wrong:** `serviceSubscriberCellularProviders?.values.first?.carrierName` returns nil or a generic string.
**Why it happens:** `CTCarrier` was deprecated in iOS 16.4 with no replacement. Apple returns static/nil values when built with iOS 16.4+ SDK.
**How to avoid:** Always handle nil. Store "Unknown" as the fallback carrier name. Do not crash or skip event logging because carrier is unavailable. The field is best-effort per MON-05.
**Warning signs:** All events have nil carrierName. This is acceptable if the device/OS combination does not support it.

### Pitfall 5: Race Between Path Update and Probe Result
**What goes wrong:** A probe fires, the path changes to unsatisfied before the probe response arrives, and the probe failure is misclassified as a silent failure because the coordinator checked stale state.
**Why it happens:** The probe is async. Path updates arrive on a different queue. Without synchronization, the coordinator's state can change between probe initiation and result processing.
**How to avoid:** Capture the path state (status, interface) at probe initiation time, not at result processing time. Pass the captured state into the result handler so classification uses the state that was current when the probe was sent.
**Warning signs:** Silent failure events logged when the path was actually unsatisfied at the time.

### Pitfall 6: Duplicate Events from Rapid Path Flapping
**What goes wrong:** NWPathMonitor fires multiple rapid callbacks during a single network transition (e.g., cellular drops, then requiresConnection, then unsatisfied in quick succession), producing multiple events for what the user perceives as one drop.
**Why it happens:** iOS sends intermediate path states during transitions.
**How to avoid:** Implement a small debounce window (e.g., 500ms) for path changes. If multiple callbacks arrive within the window, only process the final state. This reduces noise without losing real transitions.
**Warning signs:** Multiple path change events within 1 second with incremental status changes.

### Pitfall 7: Forgetting to Capture isExpensive/isConstrained
**What goes wrong:** Events are logged without the `isExpensive` and `isConstrained` flags, losing useful metadata.
**Why it happens:** These flags are easy to overlook since they don't affect classification logic.
**How to avoid:** Always read `path.isExpensive` and `path.isConstrained` in the path update handler and pass them to every event.
**Warning signs:** All events have `isExpensive = false` and `isConstrained = false` even on cellular.

## Code Examples

### NWPathMonitor Setup and Lifecycle
```swift
// Source: Apple Developer Documentation - NWPathMonitor
private func setupPathMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
        guard let self else { return }
        Task { @MainActor in
            self.handlePathUpdate(path)
        }
    }
    pathMonitor.start(queue: monitorQueue)
}

// Stop monitoring cleanly
private func teardownPathMonitor() {
    pathMonitor.cancel()
    // Note: NWPathMonitor cannot be restarted after cancel().
    // A new instance must be created for restart.
}
```

### Probe Timer Lifecycle (Foreground Only)
```swift
// Source: Foundation Timer documentation
func startProbeTimer() {
    // Timer must be scheduled on main RunLoop
    probeTimer = Timer.scheduledTimer(
        withTimeInterval: probeInterval,
        repeats: true
    ) { [weak self] _ in
        guard let self else { return }
        Task {
            await self.runProbe()
        }
    }
    // Run first probe immediately
    Task { await runProbe() }
}

func stopProbeTimer() {
    probeTimer?.invalidate()
    probeTimer = nil
}
```

### CTTelephonyNetworkInfo Radio Tech Observation
```swift
// Source: Apple Developer Documentation - CTTelephonyNetworkInfo
private func setupRadioTechObserver() {
    // Notification fires when radio tech changes (e.g., LTE -> 5G NR)
    networkInfo.serviceCurrentRadioAccessTechnologyDidUpdateNotifier = { [weak self] serviceID in
        guard let self else { return }
        let newTech = self.networkInfo.serviceCurrentRadioAccessTechnology?[serviceID]
        Task { @MainActor in
            self.currentRadioTechnology = newTech
        }
    }
    // Capture initial value
    currentRadioTechnology = networkInfo.serviceCurrentRadioAccessTechnology?.values.first
}
```

### Event Creation Helper
```swift
// Helper that enriches events with current telemetry and location
private func logEvent(
    type: EventType,
    status: PathStatus? = nil,
    interface: InterfaceType? = nil,
    isExpensive: Bool? = nil,
    isConstrained: Bool? = nil,
    probeLatencyMs: Double? = nil,
    probeFailureReason: String? = nil,
    dropDuration: Double? = nil
) {
    let event = ConnectivityEvent(
        eventType: type,
        pathStatus: status ?? currentPathStatus,
        interfaceType: interface ?? currentInterfaceType,
        isExpensive: isExpensive ?? false,
        isConstrained: isConstrained ?? false,
        radioTechnology: captureRadioTechnology(),
        carrierName: captureCarrierName(),
        probeLatencyMs: probeLatencyMs,
        probeFailureReason: probeFailureReason,
        latitude: lastLocation?.latitude,
        longitude: lastLocation?.longitude,
        locationAccuracy: lastLocation?.accuracy,
        dropDurationSeconds: dropDuration
    )

    Task {
        try? await eventStore.insertEvent(event)
    }
}
```

### ConnectivityMonitor Integration with App
```swift
// In CellGuardApp.swift:
@main
struct CellGuardApp: App {
    let container: ModelContainer

    @State private var monitor: ConnectivityMonitor

    init() {
        let container = try! ModelContainer(for: ConnectivityEvent.self)
        self.container = container
        let store = EventStore(modelContainer: container)
        _monitor = State(initialValue: ConnectivityMonitor(eventStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitor)
        }
        .modelContainer(container)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SCNetworkReachability / Reachability.swift | NWPathMonitor | iOS 12 (2018) | NWPathMonitor is simpler, more accurate, handles all interface types |
| CTCarrier for carrier info | No replacement (deprecated) | iOS 16.4 (2023) | Carrier name best-effort only. May return nil on newer devices/OS. |
| ObservableObject for service state | @Observable (Observation framework) | iOS 17 (2023) | More efficient, simpler syntax, automatic view updates |
| Combine publishers for network state | Swift Concurrency (async/await, actors) | Swift 5.5+ (2021) | Combine in maintenance mode. async/await is the standard. |
| currentRadioAccessTechnology (single SIM) | serviceCurrentRadioAccessTechnology (multi-SIM) | iOS 12 (2018) | Dictionary keyed by service ID supports dual SIM. Old property deprecated. |

**Deprecated/outdated:**
- `SCNetworkReachability` / `Reachability.swift`: Replaced by NWPathMonitor in iOS 12. Do not use.
- `CTCarrier`: Deprecated iOS 16.4. Returns nil/static values. Use best-effort only.
- `currentRadioAccessTechnology` (non-service variant): Single-SIM only. Use `serviceCurrentRadioAccessTechnology` dictionary.
- `Combine` for network state: Maintenance mode. Use @Observable + async/await.

## Open Questions

1. **NWPathMonitor callback delivery on iOS 26 with Swift 6.2 strict concurrency**
   - What we know: pathUpdateHandler is a regular closure delivered on the assigned DispatchQueue. In Swift 6.2, closures crossing actor boundaries need @Sendable compliance.
   - What's unclear: Whether NWPathMonitor's pathUpdateHandler closure is marked @Sendable in the iOS 26 SDK headers. If not, the compiler may emit warnings.
   - Recommendation: Wrap the handler body in `Task { @MainActor in ... }` to dispatch to main actor. If Sendable warnings appear, add explicit `@Sendable` annotation to the closure. This is a minor compiler concern, not a functional risk.

2. **CTTelephonyNetworkInfo behavior on iPhone 17 Pro Max with iOS 26**
   - What we know: `serviceCurrentRadioAccessTechnology` works on iOS 18. `CTCarrier` returns nil on most devices post-iOS 16.4.
   - What's unclear: Whether iOS 26 further restricts CoreTelephony access. There are no known announcements of additional deprecation.
   - Recommendation: Build with fallback to "Unknown" for both radio tech and carrier name. Test on physical device early. If radio tech also returns nil on iOS 26, the monitoring still functions -- it just logs less metadata.

3. **Probe URL: captive.apple.com vs apple.com/library/test/success.html**
   - What we know: CLAUDE.md specifies `apple.com/library/test/success.html`. Web sources commonly reference `captive.apple.com/hotspot-detect.html`. Both are Apple-hosted captive portal detection endpoints.
   - What's unclear: Which is more reliable or current in iOS 26.
   - Recommendation: Use `https://captive.apple.com/hotspot-detect.html` -- it is the more commonly documented endpoint and is specifically designed for connectivity checks. If it fails, fall back to testing with the alternative URL.

## Sources

### Primary (HIGH confidence)
- [NWPathMonitor - Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor) - Path monitoring API, pathUpdateHandler, start/cancel lifecycle
- [NWPath - Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpath) - Status enum, usesInterfaceType(), availableInterfaces, isExpensive, isConstrained
- [usesInterfaceType(_:) - Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpath/usesinterfacetype(_:)) - Interface detection method
- [serviceCurrentRadioAccessTechnology - Apple Developer Documentation](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology) - Radio tech dictionary API
- [CTCarrier Deprecation - Apple Developer Forums](https://developer.apple.com/forums/thread/714876) - Carrier info deprecated iOS 16.4

### Secondary (MEDIUM confidence)
- [Hacking with Swift - NWPathMonitor](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor) - NWPathMonitor usage patterns
- [AppCoda - Network Framework](https://www.appcoda.com/network-framework/) - Interface change detection patterns
- [SwiftLee - URLSessionConfiguration](https://www.avanderlee.com/swift/urlsessionconfiguration/) - Timeout configuration, waitsForConnectivity
- [Use Your Loaf - Network Path Monitoring](https://useyourloaf.com/blog/network-path-monitoring/) - Path monitoring patterns
- [avanderlee.com - Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/) - Swift 6.2 concurrency model

### Tertiary (LOW confidence)
- [Apple Developer Forums - Timer background behavior](https://developer.apple.com/forums/thread/127444) - Confirmation that Timer does not fire in background
- [Medium - Core Telephony for Cellular Network Info](https://medium.com/@ios_guru/core-telephony-for-accessing-cellular-network-information-b1919cc76acb) - CoreTelephony usage patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All first-party frameworks with stable, well-documented APIs. NWPathMonitor unchanged since iOS 12. URLSession HEAD is trivial. CTTelephonyNetworkInfo works on iOS 18+.
- Architecture: HIGH - Coordinator pattern is straightforward. State tracking for classification is the main complexity but the logic is deterministic. Phase 1 provides the complete data layer.
- Pitfalls: HIGH - NWPathMonitor initial callback, multi-interface detection, Timer background behavior, CTCarrier deprecation are all well-documented and understood.
- Event classification: MEDIUM - The silent failure detection (MON-03) and Wi-Fi fallback detection (MON-06) require careful state tracking. The probe race condition (Pitfall 5) needs explicit handling. These are design challenges, not API unknowns.

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable APIs, no expected changes mid-cycle)
