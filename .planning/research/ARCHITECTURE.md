# Architecture Research

**Domain:** iOS background cellular connectivity monitoring
**Researched:** 2026-03-25
**Confidence:** HIGH

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Presentation Layer                          │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────┐              │
│  │Dashboard │  │ Event Detail │  │   Export     │              │
│  │  View    │  │    View      │  │   View      │              │
│  └────┬─────┘  └──────┬───────┘  └──────┬──────┘              │
│       │               │                 │                      │
├───────┴───────────────┴─────────────────┴──────────────────────┤
│                     ViewModel Layer                             │
│  ┌──────────────────────────────────┐  ┌────────────────┐      │
│  │      MonitoringViewModel         │  │  ExportViewModel│      │
│  │  (@Observable, @MainActor)       │  │                │      │
│  └──────────────┬───────────────────┘  └───────┬────────┘      │
│                 │                               │              │
├─────────────────┴───────────────────────────────┴──────────────┤
│                     Service Layer                               │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────┐              │
│  │Connectivity │ │  Location    │ │  Telephony │              │
│  │  Monitor    │ │  Service     │ │  Service   │              │
│  └──────┬──────┘ └──────┬───────┘ └─────┬──────┘              │
│         │               │               │                      │
│  ┌──────┴───────────────┴───────────────┴──────┐               │
│  │           MonitoringCoordinator             │               │
│  │  (Orchestrates all monitors, emits events)  │               │
│  └──────────────────┬──────────────────────────┘               │
│                     │                                          │
├─────────────────────┴──────────────────────────────────────────┤
│                     Persistence Layer                           │
│  ┌──────────────────────────────────────────┐                  │
│  │          EventStore (SwiftData)           │                  │
│  │  ModelContainer → ModelContext per actor   │                  │
│  └──────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **ConnectivityMonitor** | Wraps NWPathMonitor + periodic HEAD requests; detects path changes and silent failures | Actor with NWPathMonitor on dedicated queue + URLSession timer |
| **LocationService** | Manages CLLocationManager for significant location changes; provides coarse location per event | Actor wrapping CLLocationManager delegate |
| **TelephonyService** | Reads radio access technology and carrier info from CTTelephonyNetworkInfo | Thin wrapper, read-only, called on demand |
| **MonitoringCoordinator** | Orchestrates all three monitors; assembles complete ConnectivityEvent records; manages background lifecycle | Central actor that owns the monitoring pipeline |
| **EventStore** | Persists ConnectivityEvent records via SwiftData; provides queries for UI and export | ModelActor for background writes, @Query for UI reads |
| **MonitoringViewModel** | Drives dashboard UI; subscribes to coordinator state + queries EventStore | @Observable @MainActor class |
| **ExportViewModel** | Generates CSV/JSON from EventStore; manages export flow | @Observable @MainActor class |
| **Dashboard/Detail/Export Views** | Pure SwiftUI views; display state, no business logic | SwiftUI Views with @Query and @Bindable |

## Recommended Project Structure

```
CellGuard/
├── CellGuardApp.swift              # App entry point, ModelContainer setup
├── Info.plist                      # Background modes, location usage descriptions
├── Models/
│   ├── ConnectivityEvent.swift     # SwiftData @Model — the core data record
│   ├── PathStatus.swift            # Enum: satisfied, unsatisfied, requiresConnection
│   ├── ConnectivityTestResult.swift # Enum: success, failure(code), timeout
│   └── DropSession.swift           # Groups consecutive drop events into sessions
├── Services/
│   ├── ConnectivityMonitor.swift   # NWPathMonitor + HEAD request timer
│   ├── LocationService.swift       # CLLocationManager significant changes
│   ├── TelephonyService.swift      # CTTelephonyNetworkInfo wrapper
│   └── MonitoringCoordinator.swift # Orchestrates services, emits events
├── Persistence/
│   ├── EventStore.swift            # ModelActor for background SwiftData writes
│   └── EventQueries.swift          # Predefined FetchDescriptor helpers
├── ViewModels/
│   ├── MonitoringViewModel.swift   # Dashboard state
│   └── ExportViewModel.swift       # Export generation
├── Views/
│   ├── DashboardView.swift         # Current status, drop counts, event list
│   ├── EventDetailView.swift       # Full metadata for one event
│   ├── EventListView.swift         # Scrollable filtered event log
│   ├── ExportView.swift            # CSV/JSON export controls
│   └── SummaryView.swift           # Aggregate statistics
└── Utilities/
    ├── DateFormatting.swift         # Shared date formatters
    └── Constants.swift              # Check interval, URLs, thresholds
```

### Structure Rationale

- **Models/:** SwiftData models and enums are the lingua franca. Every layer depends on these, nothing else depends on everything else. Keeping them isolated means the persistence schema is always clear.
- **Services/:** Each service wraps exactly one iOS framework (Network, CoreLocation, CoreTelephony). This isolation makes each independently testable and prevents tangled framework dependencies.
- **Persistence/:** Separated from Models because SwiftData's ModelActor threading is tricky. The EventStore actor encapsulates all thread-safety concerns in one place.
- **ViewModels/:** Thin layer that bridges Services and Views. Uses @Observable (not ObservableObject) for modern SwiftUI integration.
- **Views/:** Pure presentation. No framework imports beyond SwiftUI. Use @Query for reads directly from SwiftData where possible.

## Architectural Patterns

### Pattern 1: Actor-Based Service Isolation

**What:** Each iOS framework wrapper is a Swift actor, ensuring thread safety by construction. The coordinator is also an actor that composes them.
**When to use:** Always, for any service that touches iOS frameworks from background queues.
**Trade-offs:** Actors add async/await ceremony. Worth it because NWPathMonitor callbacks arrive on arbitrary queues, CLLocationManager has main-thread affinity requirements, and SwiftData contexts are not thread-safe.

**Example:**
```swift
actor ConnectivityMonitor {
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "cellguard.pathmonitor")
    private var checkTimer: Task<Void, Never>?

    var currentPath: NWPath? { pathMonitor.currentPath }

    func start(onChange: @Sendable (NWPath) -> Void) {
        pathMonitor.pathUpdateHandler = { path in
            onChange(path)
        }
        pathMonitor.start(queue: monitorQueue)
        startPeriodicChecks()
    }

    private func startPeriodicChecks() {
        checkTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await performConnectivityCheck()
            }
        }
    }

    private func performConnectivityCheck() async -> ConnectivityTestResult {
        var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            return httpResponse?.statusCode == 200 ? .success : .failure(httpResponse?.statusCode ?? 0)
        } catch {
            return .timeout
        }
    }
}
```

### Pattern 2: Coordinator as Event Assembler

**What:** The MonitoringCoordinator receives raw signals from each service (path change, location update, radio info) and assembles them into complete ConnectivityEvent records before persisting. No service writes to the database directly.
**When to use:** When multiple data sources must be combined into a single record.
**Trade-offs:** Slight indirection, but prevents partial/inconsistent event records and keeps services decoupled from persistence.

**Example:**
```swift
actor MonitoringCoordinator {
    private let connectivity: ConnectivityMonitor
    private let location: LocationService
    private let telephony: TelephonyService
    private let store: EventStore

    func handlePathChange(_ path: NWPath) async {
        let radioInfo = await telephony.currentRadioAccess()
        let lastLocation = await location.lastKnownLocation()
        let testResult = await connectivity.performConnectivityCheck()

        let event = ConnectivityEvent(
            timestamp: .now,
            pathStatus: path.status.mapped,
            interfaceType: path.availableInterfaces.first?.type.mapped,
            radioTechnology: radioInfo,
            location: lastLocation,
            connectivityTestResult: testResult
        )
        await store.save(event)
    }
}
```

### Pattern 3: SwiftData ModelActor for Background Writes

**What:** All database writes happen on a dedicated ModelActor, never on the main thread. UI reads use @Query which SwiftData manages automatically on @MainActor.
**When to use:** Always. Background monitoring events arrive on background queues. Writing to a main-thread ModelContext from there will crash.
**Trade-offs:** Cannot pass SwiftData model objects across actor boundaries (not Sendable). Must pass PersistentIdentifier or plain structs instead.

**Example:**
```swift
@ModelActor
actor EventStore {
    func save(_ event: ConnectivityEvent) throws {
        modelContext.insert(event)
        try modelContext.save()
    }

    func eventsInRange(from: Date, to: Date) throws -> [ConnectivityEvent] {
        let descriptor = FetchDescriptor<ConnectivityEvent>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp <= to },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
```

### Pattern 4: @Observable ViewModels on @MainActor

**What:** ViewModels use the @Observable macro and are bound to @MainActor. They call into actors asynchronously and expose published state that SwiftUI tracks automatically.
**When to use:** For all view state management in this app.
**Trade-offs:** Simpler than ObservableObject + @Published. Requires iOS 17+ (not an issue since we target iOS 26).

## Data Flow

### Event Detection Flow (Primary)

```
NWPathMonitor (path change callback)
    ↓ (on monitorQueue)
ConnectivityMonitor.onPathChange
    ↓ (async)
MonitoringCoordinator.handlePathChange
    ├── TelephonyService.currentRadioAccess() → radio tech string
    ├── LocationService.lastKnownLocation() → CLLocation?
    └── ConnectivityMonitor.performConnectivityCheck() → success/fail/timeout
    ↓ (assembles ConnectivityEvent)
EventStore.save(event)
    ↓ (SwiftData)
SQLite on disk
    ↓ (@Query auto-refresh)
DashboardView updates
```

### Periodic Health Check Flow

```
Task.sleep(60 seconds) loop
    ↓
ConnectivityMonitor.performConnectivityCheck()
    ↓ (if failure detected but NWPath says "satisfied")
MonitoringCoordinator.handleSilentFailure
    ├── Same enrichment pipeline as above
    ↓
EventStore.save(event) with type: .silentFailure
```

### Background Wake Flow

```
iOS terminates/suspends app
    ↓
CLLocationManager significant location change fires
    ↓
iOS relaunches app in background
    ↓
AppDelegate/ScenePhase handler detects background launch
    ↓
MonitoringCoordinator.resumeMonitoring()
    ├── Restarts NWPathMonitor
    ├── Restarts periodic check timer
    └── Logs a "monitoring resumed" event
```

### Export Flow

```
User taps "Export" in ExportView
    ↓
ExportViewModel.generateExport(format: .csv)
    ↓
EventStore.eventsInRange(from:to:) → [ConnectivityEvent]
    ↓
CSV/JSON serialization
    ↓
ShareSheet (UIActivityViewController via SwiftUI)
```

### Key Data Flows

1. **Path change detection:** NWPathMonitor callback arrives on a background DispatchQueue, is forwarded to the coordinator actor which enriches it with telephony/location data, then persists via EventStore actor. The UI sees changes automatically via SwiftData's @Query.

2. **Silent failure detection:** The 60-second HEAD request timer runs inside a Swift concurrency Task. When the path reports "satisfied" but the HEAD request fails, this is the critical "attached but unreachable" scenario. The coordinator logs it as a distinct event type.

3. **Background lifecycle:** Significant location changes are the primary keep-alive mechanism. When iOS relaunches the app after termination, the app delegate detects this and restarts all monitors. The NWPathMonitor itself does NOT survive app suspension -- it must be restarted.

## Background Execution Strategy

This is the most architecturally critical aspect. iOS aggressively suspends and terminates background apps.

### Layered Background Approach

| Mechanism | Purpose | Survives Suspension? | Survives Termination? |
|-----------|---------|---------------------|-----------------------|
| NWPathMonitor | Real-time path changes | NO -- stops delivering | NO |
| URLSession periodic checks | Silent failure detection | NO -- timer stops | NO |
| Significant location changes | App relaunch trigger | YES (system-managed) | YES (relaunches app) |
| Background App Refresh | Periodic wake opportunity | YES (system-scheduled) | NO |
| BGProcessingTask | Extended background time | YES (when granted) | NO |

### Strategy

1. **Primary keep-alive:** `startMonitoringSignificantLocationChanges()` -- this is the ONLY mechanism that relaunches a terminated app. It fires when the device moves ~500m or connects to a different cell tower. For a phone carried around daily, this fires frequently enough.

2. **Active monitoring window:** When the app is running (foreground or recently backgrounded), NWPathMonitor + periodic HEAD checks provide real-time detection. This is the high-fidelity window.

3. **Background App Refresh:** Register for background refresh to get periodic wake windows. When woken, run a quick HEAD check and log the result. System decides frequency (typically 15-60 min).

4. **On relaunch:** Detect whether the app was relaunched by significant location change (check `UIApplication.LaunchOptionsKey.location`) and immediately restart all monitors + run an immediate connectivity check.

### Critical Constraint

There is a gap: between app suspension and the next significant location change or background refresh, monitoring is blind. This is an inherent iOS limitation. The architecture must log this gap honestly -- record when monitoring started and stopped so the exported data shows coverage windows.

## Anti-Patterns

### Anti-Pattern 1: Single Main-Thread ModelContext for Everything

**What people do:** Use the @Environment(\.modelContext) from SwiftUI views to write events from background callbacks.
**Why it's wrong:** Background callbacks arrive on non-main queues. Writing to a main-thread ModelContext from a background queue causes crashes or data corruption. SwiftData model objects are not Sendable.
**Do this instead:** Use a dedicated @ModelActor for all background writes. Only use the view's ModelContext for @Query reads (which SwiftData handles safely).

### Anti-Pattern 2: Continuous GPS for Background Execution

**What people do:** Use `startUpdatingLocation()` with background location mode to keep the app alive permanently.
**Why it's wrong:** Drains battery rapidly (the exact thing we're trying to avoid). Apple reviews flag this pattern. The blue location bar annoys users. For a personal tool with free signing, Apple won't reject it, but the battery cost is unacceptable for 24/7 monitoring.
**Do this instead:** Use `startMonitoringSignificantLocationChanges()` which uses cell tower triangulation (near-zero battery cost) and provides coarse location that's sufficient for geographic pattern analysis.

### Anti-Pattern 3: Background URLSession for Periodic Checks

**What people do:** Use URLSession background configuration for periodic connectivity checks, thinking it survives suspension.
**Why it's wrong:** Background URLSession is for discrete downloads/uploads, not periodic polling. The system decides when to execute these transfers. You cannot control timing.
**Do this instead:** Use a regular URLSession with a Task-based timer for checks while the app is running. Accept that checks pause during suspension. Use significant location changes to get relaunched and resume checking.

### Anti-Pattern 4: Storing NWPath Objects

**What people do:** Store NWPath objects in the database or pass them across actor boundaries.
**Why it's wrong:** NWPath is a snapshot that becomes stale. It's not Codable. It references internal state.
**Do this instead:** Immediately extract the relevant properties (status, interface type, expensive/constrained flags) into your own Codable model types and discard the NWPath.

### Anti-Pattern 5: Ignoring the Monitoring Gap

**What people do:** Assume the app is always monitoring and present the event log as if coverage is continuous.
**Why it's wrong:** The log has gaps whenever the app was suspended/terminated. Without acknowledging this, absence of events looks like "no drops" when it actually means "wasn't watching."
**Do this instead:** Log monitoring start/stop events. Track "uptime" separately. In the export, include coverage windows so Apple's engineers can distinguish "monitored and stable" from "not monitoring."

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Apple captive portal (`apple.com/library/test/success.html`) | HEAD request via URLSession, 10s timeout | Apple-hosted, always available, same endpoint iOS uses internally. No privacy concern. Only check is HTTP 200 response. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Services → Coordinator | Async callbacks / actor method calls | Services never talk to each other directly. Coordinator orchestrates. |
| Coordinator → EventStore | Actor method calls with plain struct parameters | Pass assembled ConnectivityEvent values, not framework objects (NWPath, CLLocation). EventStore creates the @Model instance. |
| EventStore → Views | SwiftData @Query (automatic) | Views never call EventStore directly. @Query on ModelContainer provides reactive updates. ViewModels may call EventStore for complex queries (export, date range aggregation). |
| App lifecycle → Coordinator | ScenePhase / AppDelegate callbacks | Background launch detection triggers coordinator restart. Foreground return triggers immediate health check. |

## Build Order (Dependency Graph)

Components should be built in this order based on dependencies:

```
Phase 1: Foundation
  Models (ConnectivityEvent, enums)  ← no dependencies
  EventStore (SwiftData persistence) ← depends on Models
  App shell + ModelContainer setup   ← depends on EventStore

Phase 2: Core Monitoring
  ConnectivityMonitor (NWPathMonitor + HEAD checks)  ← depends on Models
  TelephonyService (CTTelephonyNetworkInfo wrapper)   ← depends on Models
  LocationService (CLLocationManager wrapper)         ← depends on Models
  MonitoringCoordinator (orchestrator)                ← depends on all three + EventStore

Phase 3: Background Lifecycle
  Background mode configuration (Info.plist)
  App launch detection (background vs foreground)
  Coordinator start/stop/resume lifecycle
  Monitoring gap tracking

Phase 4: UI
  DashboardView + MonitoringViewModel
  EventDetailView
  EventListView with filtering

Phase 5: Export & Polish
  ExportViewModel + CSV/JSON generation
  SummaryView (aggregate statistics)
  ShareSheet integration
```

**Build order rationale:**
- Models first because everything depends on them.
- EventStore before services because you want to verify persistence works before generating real events.
- Services can be built in parallel (independent of each other), but the coordinator depends on all three.
- Background lifecycle is a separate concern that wraps around the coordinator -- build it after the coordinator works in foreground.
- UI last because it's purely presentation. During earlier phases, verify behavior via console logs. The UI is just a window into data that already works.

## Sources

- [NWPathMonitor documentation](https://developer.apple.com/documentation/network/nwpathmonitor) -- Apple official
- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) -- Apple official
- [startMonitoringSignificantLocationChanges()](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()) -- Apple official
- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background) -- Apple official
- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) -- Apple official (iOS 26 new API)
- [WWDC 2025: Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/) -- Apple official
- [iOS 16 CTCarrier deprecation](https://developer.apple.com/forums/thread/714876) -- Apple Developer Forums
- [SwiftData background tasks](https://useyourloaf.com/blog/swiftdata-background-tasks/) -- Use Your Loaf (HIGH confidence, well-known iOS resource)
- [Concurrent programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/) -- Fat Bob Man (HIGH confidence, detailed technical reference)
- [SwiftData background context](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-background-context) -- Hacking with Swift (HIGH confidence)

---
*Architecture research for: iOS background cellular connectivity monitoring*
*Researched: 2026-03-25*
