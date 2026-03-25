# Phase 1: Foundation - Research

**Researched:** 2026-03-25
**Domain:** SwiftData persistence layer, data modeling, background context writes
**Confidence:** MEDIUM

## Summary

Phase 1 establishes the ConnectivityEvent data model and persistence layer using SwiftData. The core challenge is not the model definition itself -- which is straightforward -- but getting background writes via `@ModelActor` to work reliably and ensuring the UI stays in sync. There is a known, unresolved bug in iOS 18+ where `@Query` does not refresh after `@ModelActor` background inserts, requiring a workaround strategy from day one.

The data model must store ~15 metadata fields per event. Two design constraints require specific patterns: (1) `CLLocationCoordinate2D` is not directly storable in SwiftData -- store latitude/longitude as separate `Double` properties with a computed accessor, and (2) enums cannot be used in SwiftData predicates -- store the `rawValue` with a computed enum accessor for any field that needs filtering.

**Primary recommendation:** Use SwiftData with `@Model` for the ConnectivityEvent, `@ModelActor` for background writes, and implement the rawValue pattern for all enum fields from the start. For the `@Query` refresh bug, use `NSPersistentStoreRemoteChange` notification observation as the workaround.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DAT-01 | Each event stored with full metadata: ISO 8601 timestamp (local + UTC), event type, path status, interface type, is_expensive, is_constrained, radio technology, carrier name, probe result (latency or failure reason), coarse location | SwiftData `@Model` supports all needed types (String, Date, Double, Int, Bool, Codable enums). CLLocationCoordinate2D requires latitude/longitude Double decomposition. Enums need rawValue storage pattern for predicate support. |
| DAT-06 | App stores weeks of event data locally without significant storage impact using SwiftData | SwiftData adequate for ~10,000 rows/week. ModelContainer with default SQLite backend. No special configuration needed for this volume. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ (ships with iOS 26 SDK) | Event persistence | First-party, native SwiftUI integration via `@Query`, `@Model` macro for schema, `@ModelActor` for background writes. No external dependencies. |
| Swift 6.2 | Xcode 26 | Language | Approachable Concurrency simplifies actor-based background work. Strict concurrency checking catches data races at compile time. |
| SwiftUI | iOS 26 SDK | App shell UI | `.modelContainer()` modifier wires persistence into view hierarchy. `@Query` provides live-updating views. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation (`JSONEncoder`) | Built-in | Codable conformance for export-ready models | Model should conform to `Codable` from day one for future JSON export (Phase 4). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData | GRDB.swift | Better performance, direct SQLite, but adds external dependency. Not warranted at ~1,440 events/day. |
| SwiftData | Core Data | SwiftData is built on Core Data. No reason to use Core Data directly for a new iOS 26 project. |

## Architecture Patterns

### Recommended Project Structure
```
CellGuard/
├── CellGuardApp.swift           # @main, ModelContainer setup
├── Models/
│   └── ConnectivityEvent.swift  # @Model class + enums
├── Services/
│   └── EventStore.swift         # @ModelActor for background writes
├── Views/
│   └── ContentView.swift        # Minimal shell (placeholder for Phase 4)
└── Info.plist
```

### Pattern 1: ConnectivityEvent Data Model
**What:** A `@Model` class with all DAT-01 metadata fields, using the rawValue pattern for enums and Double decomposition for coordinates.
**When to use:** This is the single model for the entire app.
**Example:**
```swift
// Source: SwiftData @Model documentation + fatbobman.com enum guidance
import SwiftData
import Foundation

enum EventType: Int, Codable, CaseIterable {
    case pathChange = 0
    case silentFailure = 1
    case probeSuccess = 2
    case probeFailure = 3
    case connectivityRestored = 4
}

enum PathStatus: Int, Codable {
    case satisfied = 0
    case unsatisfied = 1
    case requiresConnection = 2
}

enum InterfaceType: Int, Codable {
    case cellular = 0
    case wifi = 1
    case wiredEthernet = 2
    case loopback = 3
    case other = 4
    case unknown = 5
}

@Model
final class ConnectivityEvent {
    // Timestamps
    var timestamp: Date
    var timestampUTC: Date  // Same instant, stored for export clarity

    // Event classification -- store rawValue for predicate support
    var eventTypeRaw: Int
    var eventType: EventType {
        get { EventType(rawValue: eventTypeRaw) ?? .pathChange }
        set { eventTypeRaw = newValue.rawValue }
    }

    // Network path state
    var pathStatusRaw: Int
    var pathStatus: PathStatus {
        get { PathStatus(rawValue: pathStatusRaw) ?? .unsatisfied }
        set { pathStatusRaw = newValue.rawValue }
    }

    var interfaceTypeRaw: Int
    var interfaceType: InterfaceType {
        get { InterfaceType(rawValue: interfaceTypeRaw) ?? .unknown }
        set { interfaceTypeRaw = newValue.rawValue }
    }

    var isExpensive: Bool
    var isConstrained: Bool

    // Cellular metadata
    var radioTechnology: String?   // e.g. "CTRadioAccessTechnologyNR", nil if unknown
    var carrierName: String?       // May be nil due to CTCarrier deprecation

    // Active probe results
    var probeLatencyMs: Double?    // nil if probe not performed
    var probeFailureReason: String? // nil if probe succeeded or not performed

    // Location (decomposed from CLLocationCoordinate2D)
    var latitude: Double?
    var longitude: Double?
    var locationAccuracy: Double?  // horizontalAccuracy in meters

    // Drop duration (calculated in Phase 2, nil until then)
    var dropDurationSeconds: Double?

    init(
        timestamp: Date = .now,
        eventType: EventType,
        pathStatus: PathStatus,
        interfaceType: InterfaceType,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        radioTechnology: String? = nil,
        carrierName: String? = nil,
        probeLatencyMs: Double? = nil,
        probeFailureReason: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracy: Double? = nil,
        dropDurationSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.timestampUTC = timestamp  // Same Date object, formatting handles TZ
        self.eventTypeRaw = eventType.rawValue
        self.pathStatusRaw = pathStatus.rawValue
        self.interfaceTypeRaw = interfaceType.rawValue
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.radioTechnology = radioTechnology
        self.carrierName = carrierName
        self.probeLatencyMs = probeLatencyMs
        self.probeFailureReason = probeFailureReason
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracy = locationAccuracy
        self.dropDurationSeconds = dropDurationSeconds
    }
}
```

### Pattern 2: EventStore with @ModelActor
**What:** A dedicated actor for background writes that accepts a `ModelContainer` and provides methods to insert events.
**When to use:** All event persistence from monitoring services (Phase 2+) goes through this actor.
**Example:**
```swift
// Source: useyourloaf.com/blog/swiftdata-background-tasks + brightdigit.com
import SwiftData
import Foundation

@ModelActor
actor EventStore {

    func insertEvent(_ event: ConnectivityEvent) throws {
        modelContext.insert(event)
        try modelContext.save()
    }

    func fetchEvents(limit: Int = 100) throws -> [ConnectivityEvent] {
        var descriptor = FetchDescriptor<ConnectivityEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func deleteAllEvents() throws {
        try modelContext.delete(model: ConnectivityEvent.self)
        try modelContext.save()
    }
}

// Initialization (from app or service):
// let store = EventStore(modelContainer: container)
// try await store.insertEvent(event)
```

### Pattern 3: ModelContainer Setup at App Level
**What:** Configure `ModelContainer` once in the `@main` App struct and inject via `.modelContainer()`.
**When to use:** App entry point.
**Example:**
```swift
// Source: hackingwithswift.com/quick-start/swiftdata + Apple docs
import SwiftUI
import SwiftData

@main
struct CellGuardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ConnectivityEvent.self)
    }
}
```

### Anti-Patterns to Avoid
- **Creating multiple ModelContainers:** Always share one container. Multiple containers pointing at the same store cause context conflicts and "cannot delete objects in other contexts" errors.
- **Passing @Model objects across actor boundaries:** SwiftData models are NOT `Sendable`. Pass `PersistentIdentifier` values across boundaries, then re-fetch using `modelContext.model(for:)`.
- **Using enum types directly in `#Predicate`:** SwiftData does not support enum predicates as of iOS 18. Always filter on the `rawValue` property (e.g., `eventTypeRaw`) instead.
- **Creating @ModelActor on the main thread without wrapping:** If initialized on `@MainActor`, all operations run on main thread. Use `Task.detached` or ensure actor initialization happens off-main.
- **Storing CLLocationCoordinate2D directly:** Not supported by SwiftData. Decompose to `latitude`/`longitude` Double properties.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data persistence | Custom SQLite wrapper | SwiftData `@Model` + `ModelContainer` | Schema management, migration, SwiftUI integration all built in |
| Background-safe writes | Manual GCD queue + context management | `@ModelActor` | Actor isolation enforced by compiler, serial execution guaranteed |
| Live UI updates from DB | Manual notification/delegate pattern | `@Query` macro | Automatic view refresh on data changes (with known caveats, see Pitfalls) |
| Date formatting | Custom formatters | ISO8601DateFormatter / `Date.ISO8601FormatStyle` | Handles timezone correctly, no edge cases |

## Common Pitfalls

### Pitfall 1: @Query Does Not Refresh After @ModelActor Background Inserts (iOS 18+)
**What goes wrong:** Views using `@Query` do not update when a `@ModelActor` inserts new records. Deletes DO trigger updates, but inserts do not. This is a confirmed regression from iOS 17 to iOS 18.
**Why it happens:** Known SwiftData bug. The main context does not merge insert notifications from background contexts correctly on iOS 18+.
**How to avoid:** Observe `NSPersistentStoreRemoteChange` notification on the main context and trigger a manual refetch. Alternatively, for this app's simple needs, the view can periodically refetch or refetch on `scenePhase` changes. Since CellGuard logs events in the background and the user views them when foregrounding, a `scenePhase`-triggered refetch may be the simplest reliable workaround.
**Warning signs:** New events appear in the database (verifiable via `fetchEvents()`) but the UI shows stale data until app restart.

### Pitfall 2: Enum Fields Not Queryable in Predicates
**What goes wrong:** Using `#Predicate { $0.eventType == .silentFailure }` crashes or returns wrong results.
**Why it happens:** SwiftData does not map enum types to their storage representation in predicates as of iOS 18.
**How to avoid:** Store the `rawValue` as a separate stored property (e.g., `eventTypeRaw: Int`). Use a computed property for the enum accessor. Filter on the raw property: `#Predicate { $0.eventTypeRaw == 1 }`.
**Warning signs:** Runtime crash with "unsupportedPredicate" error.

### Pitfall 3: CLLocationCoordinate2D Not Storable
**What goes wrong:** Compilation error or runtime crash when using `CLLocationCoordinate2D` as a `@Model` property.
**Why it happens:** `CLLocationCoordinate2D` is a C struct that does not conform to `Codable`.
**How to avoid:** Store `latitude: Double?` and `longitude: Double?` separately. Add a computed property to reconstruct `CLLocationCoordinate2D`.
**Warning signs:** Build error on `@Model` macro expansion.

### Pitfall 4: Modifying Codable Enum Cases Breaks Migration
**What goes wrong:** Adding, removing, or reordering enum cases breaks lightweight migration for existing data.
**Why it happens:** SwiftData stores Codable types by flattening their encoded representation. Changing the encoding breaks deserialization of existing rows.
**How to avoid:** Use `Int` raw values for all enums. Assign explicit raw values (don't rely on auto-increment). Never change existing case raw values -- only append new cases at the end.
**Warning signs:** App crashes on launch after model change, with migration error.

### Pitfall 5: @ModelActor Singleton Pattern Required
**What goes wrong:** Creating a new `EventStore` actor on every write creates a new `ModelContext` each time, leading to context conflicts and potential data corruption.
**Why it happens:** Each `@ModelActor` init creates a fresh `ModelContext`.
**How to avoid:** Create one `EventStore` instance and reuse it. Store it as a property on the app or pass it through the environment. Do not recreate per-call.
**Warning signs:** "NSManagedObjectContext cannot delete/update objects in other contexts" errors.

## Code Examples

### Creating and Configuring ModelContainer
```swift
// Source: Apple Developer Documentation - ModelContainer
// For Phase 1, the simplest configuration is sufficient:
let container = try ModelContainer(for: ConnectivityEvent.self)

// Or with explicit configuration for testing:
let config = ModelConfiguration(isStoredInMemoryOnly: true) // for unit tests
let testContainer = try ModelContainer(
    for: ConnectivityEvent.self,
    configurations: config
)
```

### Background Insert via EventStore
```swift
// Source: useyourloaf.com SwiftData background tasks
let store = EventStore(modelContainer: container)

// From a background context (e.g., network monitor callback):
try await store.insertEvent(ConnectivityEvent(
    eventType: .pathChange,
    pathStatus: .unsatisfied,
    interfaceType: .cellular,
    radioTechnology: "CTRadioAccessTechnologyNR"
))
```

### Querying Events in SwiftUI View
```swift
// Source: Apple Developer Documentation - @Query
struct EventListView: View {
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    var events: [ConnectivityEvent]

    var body: some View {
        List(events) { event in
            Text("\(event.eventType) at \(event.timestamp, format: .dateTime)")
        }
    }
}
```

### Workaround: Force @Query Refresh on Foreground
```swift
// Workaround for iOS 18+ @Query not refreshing after background inserts
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        EventListView()
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Force context to re-read from store
                    modelContext.processPendingChanges()
                }
            }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Core Data + NSManagedObject | SwiftData + @Model | iOS 17 (2023) | Simpler API, macro-based schema, native SwiftUI integration |
| ObservableObject + @Published | @Observable (Observation framework) | iOS 17 (2023) | More efficient updates, simpler syntax |
| Manual NSManagedObjectContext for background | @ModelActor | iOS 17 (2023) | Compiler-enforced actor isolation for background contexts |
| Core Data persistent history tracking | SwiftData History API | iOS 18 (2024) | Transaction-based change tracking with tokens |

**Deprecated/outdated:**
- `ObservableObject` / `@Published`: Legacy. Use `@Observable` for iOS 17+.
- `NSPersistentContainer`: Use `ModelContainer` for new SwiftData projects.
- Direct Core Data usage: SwiftData wraps Core Data; use SwiftData API directly.

## Open Questions

1. **@Query refresh bug status on iOS 26**
   - What we know: Bug exists on iOS 18.0-18.x. Background inserts via @ModelActor don't trigger @Query view updates.
   - What's unclear: Whether Apple fixed this in iOS 26 SDK. No iOS 26 release notes confirming a fix.
   - Recommendation: Implement the `scenePhase` workaround from day one. If iOS 26 fixes it, the workaround is harmless and can be removed later.

2. **SwiftData performance with autosave in background**
   - What we know: Autosave is enabled by default. @ModelActor calls `save()` explicitly.
   - What's unclear: Whether explicit `save()` inside a @ModelActor with autosave enabled causes any issues.
   - Recommendation: Call `save()` explicitly after inserts in the EventStore. Autosave is a safety net, not a conflict.

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation - ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) - Container setup, configuration
- [Apple Developer Documentation - @Model](https://developer.apple.com/documentation/swiftdata/model()) - Model macro, supported types
- [Apple Developer Documentation - Track model changes with SwiftData history (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10075/) - History API for change tracking

### Secondary (MEDIUM confidence)
- [SwiftData Background Tasks - useyourloaf.com](https://useyourloaf.com/blog/swiftdata-background-tasks/) - @ModelActor patterns, background context setup
- [Using ModelActor in SwiftData - BrightDigit](https://brightdigit.com/tutorials/swiftdata-modelactor/) - Singleton pattern, thread safety considerations
- [Key Considerations Before Using SwiftData - fatbobman.com](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/) - Production pitfalls, enum limitations, concurrency issues
- [Considerations for Using Codable and Enums in SwiftData Models - fatbobman.com](https://fatbobman.com/en/posts/considerations-for-using-codable-and-enums-in-swiftdata-models/) - Enum storage mechanics, predicate limitations, migration risks
- [How to define SwiftData models - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-define-swiftdata-models-using-the-model-macro) - @Model macro usage, supported field types
- [How to configure a custom ModelContainer - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-configure-a-custom-modelcontainer-using-modelconfiguration) - ModelConfiguration options
- [Filtering SwiftData Models Using Enum - AzamSharp](https://azamsharp.com/2025/01/23/filtering-swiftdata-models-using-enum.html) - rawValue workaround for enum predicates

### Tertiary (LOW confidence)
- [Apple Developer Forums - SwiftData background inserts](https://developer.apple.com/forums/thread/734177) - @Query refresh bug reports, community workarounds
- [Apple Developer Forums - CLLocationCoordinate2D in SwiftData](https://msclb.store/forums/thread/743696) - Coordinate storage workaround

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftData is the locked decision from CLAUDE.md, well-documented first-party framework
- Architecture: MEDIUM - @ModelActor patterns are well-documented but the @Query refresh bug on iOS 18+ introduces uncertainty about UI integration
- Pitfalls: HIGH - Multiple sources confirm the same issues (enum predicates, @Query refresh, CLLocationCoordinate2D)
- Data model design: MEDIUM - Field list is clear from DAT-01, but some fields (dropDurationSeconds) will be populated by later phases

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable domain, SwiftData API unlikely to change mid-cycle)
