# Phase 7: Wi-Fi Context - Research

**Researched:** 2026-04-20
**Domain:** iOS Wi-Fi SSID capture via NEHotspotNetwork, SwiftData schema extension, export integration
**Confidence:** HIGH

## Summary

Phase 7 adds Wi-Fi SSID capture to every connectivity event logged by CellGuard. The implementation touches four layers: (1) a new `wifiSSID` optional String field on the SwiftData `ConnectivityEvent` model, (2) SSID capture via `NEHotspotNetwork.fetchCurrent()` at event logging time in `ConnectivityMonitor`, (3) inclusion in JSON export with privacy-toggle redaction, and (4) display in `EventDetailView` as a conditional section.

The critical prerequisite -- the paid Apple Developer account (Team ID VTWHBCCP36) -- is already in place from Phase 6. This enables the "Access WiFi Information" entitlement (`com.apple.developer.networking.wifi-info`), which is required for `NEHotspotNetwork.fetchCurrent()` to return non-nil results. The app already has "Always" location authorization via CoreLocation (significant location changes), which satisfies the precise-location requirement for SSID access.

The primary technical risk is that `NEHotspotNetwork.fetchCurrent()` may return nil in background execution contexts. When the app is woken by a significant location change and logs an event in the background, the SSID capture should still be attempted but may silently fail. The model's optional `String?` type handles this gracefully -- nil means "SSID not available at capture time," which is distinct from "device was on cellular only."

**Primary recommendation:** Use `NEHotspotNetwork.fetchCurrent() async` (available iOS 14+) to capture SSID at event logging time in ConnectivityMonitor. Add the entitlement via Xcode Signing & Capabilities. No VersionedSchema migration needed -- SwiftData handles new optional properties automatically.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WIFI-01 | Current Wi-Fi SSID is captured at the time of each connectivity event | NEHotspotNetwork.fetchCurrent() async API; called from ConnectivityMonitor.logEvent(); returns SSID when on Wi-Fi with entitlement + location auth |
| WIFI-02 | Wi-Fi SSID is stored as a field in the SwiftData ConnectivityEvent model | New `wifiSSID: String?` property; SwiftData automatic lightweight migration handles the schema change without VersionedSchema |
| WIFI-03 | Wi-Fi SSID is included in JSON and CSV export output, respecting the existing privacy toggle | New CodingKey `wifiSSID` in Codable conformance; `encodeIfPresent` when privacy off, omitted when privacy on; CSV export does not exist yet -- requirement applies to JSON only unless CSV is built |
| WIFI-04 | Wi-Fi SSID is visible in the event detail view | New conditional `Section("Wi-Fi")` in EventDetailView per UI-SPEC contract |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SSID capture | API / Service layer (ConnectivityMonitor) | -- | NEHotspotNetwork is a system framework call; capture happens at event creation time in the monitoring service |
| SSID storage | Database / Storage (SwiftData model) | -- | New optional field on ConnectivityEvent @Model |
| SSID display | Frontend / SwiftUI view | -- | EventDetailView renders a conditional section |
| SSID export | Model layer (Codable conformance) | -- | Encode/decode logic in ConnectivityEvent's Codable extension |
| SSID privacy redaction | Model layer (encoder userInfo) | Frontend (toggle label) | Existing omitLocation pattern extended; toggle label updated in DashboardView |
| Entitlement setup | Build configuration | -- | Xcode Signing & Capabilities; entitlements file |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NetworkExtension (`NEHotspotNetwork`) | iOS 14+ (stable) | Wi-Fi SSID capture via `fetchCurrent()` | First-party Apple framework. The only supported API for SSID access on iOS 14+. CNCopyCurrentNetworkInfo is deprecated and returns nil when linked against iOS 26 SDK. [VERIFIED: Apple TN3111 via Context7] |
| SwiftData | iOS 17+ | Schema extension with new optional field | Already used by the project. Automatic lightweight migration handles new optional properties without explicit VersionedSchema. [VERIFIED: codebase scan] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CoreLocation (already integrated) | iOS 2+ | Location authorization satisfies SSID access prerequisite | Already running -- no new code needed. The app's "Always" location authorization with precise location satisfies one of the four NEHotspotNetwork requirements. [VERIFIED: codebase scan -- LocationService.swift] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NEHotspotNetwork.fetchCurrent() | CNCopyCurrentNetworkInfo | Deprecated; returns nil when linked against iOS 26 SDK. Not viable for this project targeting iOS 26. [CITED: Apple TN3111] |
| NEHotspotNetwork.fetchCurrent() | NWPathMonitor interface detection | NWPathMonitor detects Wi-Fi vs cellular interface type but does NOT provide SSID. Cannot replace NEHotspotNetwork for SSID capture. [VERIFIED: Apple developer forums] |

**Installation:** No new packages needed -- NetworkExtension is a system framework. Add `import NetworkExtension` to ConnectivityMonitor.swift.

## Architecture Patterns

### System Architecture: SSID Capture Flow

```
Significant Location Change / Path Update / Probe Timer
         |
         v
ConnectivityMonitor.logEvent()
         |
         +---> captureWifiSSID() async -> String?
         |         |
         |         +---> NEHotspotNetwork.fetchCurrent() async
         |         |         |
         |         |         +---> Returns NEHotspotNetwork? 
         |         |                  .ssid property -> String
         |         |
         |         +---> Returns nil if:
         |                 - Not on Wi-Fi
         |                 - Missing entitlement
         |                 - Missing location auth
         |                 - Background execution (may fail)
         |
         v
ConnectivityEvent(wifiSSID: capturedSSID)
         |
         v
EventStore.insertEvent() --> SwiftData persistence
         |
         v
UI (@Query) --> EventDetailView (conditional "Wi-Fi" section)
Export (Codable) --> JSON with privacy gate
```

### Pattern 1: Async SSID Capture in logEvent

**What:** The `logEvent()` method in ConnectivityMonitor must become async to await `NEHotspotNetwork.fetchCurrent()`.

**When to use:** Every time an event is logged.

**Example:**
```swift
// Source: Apple Developer Documentation + codebase pattern
import NetworkExtension

/// Captures the current Wi-Fi SSID if available.
/// Returns nil when not on Wi-Fi, missing entitlement, or in restricted background context.
private func captureWifiSSID() async -> String? {
    let network = await NEHotspotNetwork.fetchCurrent()
    return network?.ssid
}
```

**Impact on logEvent():** The existing `logEvent()` is synchronous. It must be converted to `async` so it can `await captureWifiSSID()`. All call sites (in `processPathChange`, `runProbe`, `LocationService.detectAndLogGap`) already run within `Task { @MainActor }` blocks, so adding `await` to the `logEvent()` calls is straightforward.

### Pattern 2: SwiftData Optional Field Addition (No VersionedSchema)

**What:** Add `var wifiSSID: String?` to the `@Model` class. SwiftData performs automatic lightweight migration.

**When to use:** When adding a new optional property with no default value requirement.

**Example:**
```swift
// Source: existing ConnectivityEvent.swift pattern
@Model
final class ConnectivityEvent {
    // ... existing properties ...
    
    /// Wi-Fi SSID at the time of the event. Nil if not connected to Wi-Fi
    /// or SSID could not be captured (background limitation, missing entitlement).
    var wifiSSID: String?
    
    // ... update init to accept wifiSSID parameter ...
}
```

**Migration note:** The project does NOT use `VersionedSchema` or `SchemaMigrationPlan`. The ModelContainer is created as `ModelContainer(for: ConnectivityEvent.self)` with implicit schema. Adding a new optional `String?` property triggers SwiftData's automatic lightweight migration -- existing rows get nil for the new column. No migration code needed. [CITED: hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations]

### Pattern 3: Privacy Gate Extension for SSID

**What:** Extend the existing `omitLocation` encoder userInfo pattern to also suppress `wifiSSID`.

**Example:**
```swift
// Source: existing ConnectivityEvent.swift encode(to:) pattern
func encode(to encoder: Encoder) throws {
    // ... existing fields ...
    let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
    if !omitLocation {
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
        try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)  // NEW
    }
    // ...
}
```

### Anti-Patterns to Avoid

- **Creating a new CTTelephonyNetworkInfo-style wrapper for SSID:** NEHotspotNetwork is a simple class method call. Do not create a long-lived instance or observer -- call `fetchCurrent()` at capture time. Unlike CTTelephonyNetworkInfo (which caches stale values), NEHotspotNetwork has no instance state problem.

- **Using CNCopyCurrentNetworkInfo:** Deprecated. Returns nil when linked against iOS 26 SDK. Will not work for this project. [CITED: Apple TN3111 via Context7]

- **Checking NWPath interface type as SSID substitute:** NWPathMonitor tells you the device is on Wi-Fi, but not which network. Always use NEHotspotNetwork for the actual SSID string.

- **Making logEvent synchronous and fire-and-forget for SSID:** Do not call `NEHotspotNetwork.fetchCurrent()` inside a detached Task and ignore the result. The SSID must be captured before the event is persisted so they are stored together atomically.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Wi-Fi SSID access | Manual CNCopyCurrentNetworkInfo wrapper | `NEHotspotNetwork.fetchCurrent() async` | Single method call; CNCopy is deprecated and broken on iOS 26 |
| Schema migration | Manual SQLite ALTER TABLE or VersionedSchema boilerplate | SwiftData automatic lightweight migration | Adding optional field to implicit schema just works |
| Privacy redaction for SSID | Separate privacy flag | Existing `omitLocation` userInfo pattern | SSID is geographically-sensitive data like location; same toggle applies per UI-SPEC |

**Key insight:** The entire SSID capture chain is roughly 10-15 lines of new code across 4 files. The complexity is in knowing the correct API and entitlement setup, not in implementation volume.

## Common Pitfalls

### Pitfall 1: Missing Entitlement Returns Nil Silently

**What goes wrong:** `NEHotspotNetwork.fetchCurrent()` returns nil with no error when the "Access WiFi Information" entitlement is missing. The app compiles and runs fine but never captures SSIDs.
**Why it happens:** The API does not throw -- it returns an optional. Missing entitlements are indistinguishable from "not on Wi-Fi" at the API level.
**How to avoid:** Add the entitlement via Xcode Signing & Capabilities FIRST, before writing any code. Verify the `.entitlements` file contains `com.apple.developer.networking.wifi-info = YES`. Test on a physical device connected to Wi-Fi.
**Warning signs:** All events have `wifiSSID: nil` even when device is on Wi-Fi.

### Pitfall 2: Background SSID Capture May Return Nil

**What goes wrong:** When the app is woken in the background by a significant location change, `NEHotspotNetwork.fetchCurrent()` may return nil even when the device is connected to Wi-Fi.
**Why it happens:** iOS restricts certain API access in background execution contexts. The SSID API may not be available when the app is not in the foreground. [ASSUMED]
**How to avoid:** Accept nil gracefully -- the `String?` model type handles this. Events logged from background wakes may have nil SSID while foreground events capture it reliably. This is acceptable for a diagnostic tool -- the data is best-effort context, not a critical field.
**Warning signs:** SSID populated for foreground events but consistently nil for events logged during background wakes.

### Pitfall 3: Precise Location Authorization Required

**What goes wrong:** `NEHotspotNetwork.fetchCurrent()` returns nil if the app only has approximate (not precise) location authorization.
**Why it happens:** Apple requires precise location authorization as a privacy gate for SSID access. The SSID reveals the user's exact location (home network, office network, etc.).
**How to avoid:** CellGuard already requests "Always" authorization which includes precise location. But if the user downgrades to approximate location in Settings, SSID capture will silently break.
**Warning signs:** SSID was working, then stopped after user changed location privacy settings.

### Pitfall 4: logEvent() Async Conversion Race Conditions

**What goes wrong:** Converting `logEvent()` from sync to async introduces potential timing issues if multiple events are logged concurrently.
**Why it happens:** Multiple path updates or probe results could call `logEvent()` nearly simultaneously, each awaiting `fetchCurrent()`.
**How to avoid:** The existing debounce mechanism (500ms) in `processPathChange` naturally serializes path-based events. Probe events are timer-driven (60s interval). Concurrent SSID fetches are harmless -- `fetchCurrent()` is stateless and thread-safe. Each event gets its own snapshot.
**Warning signs:** None expected -- this is a theoretical concern that the existing architecture already mitigates.

### Pitfall 5: Forgetting to Update Codable CodingKeys

**What goes wrong:** Adding `wifiSSID` to the model but forgetting to add it to the `CodingKeys` enum and `encode(to:)`/`init(from:)` means the field is silently excluded from JSON export.
**Why it happens:** The ConnectivityEvent has a manual Codable conformance (not auto-synthesized) because of the enum rawValue handling and privacy gate logic.
**How to avoid:** Update all three: (1) CodingKeys enum, (2) encode(to:) method, (3) init(from:) convenience initializer. The decode side should use `decodeIfPresent` for backward compatibility with exported JSON files that don't have the field.
**Warning signs:** Events display SSID in the detail view but exported JSON files have no `wifiSSID` key.

## Code Examples

### SSID Capture Helper (for ConnectivityMonitor)

```swift
// Source: Apple Developer Documentation NEHotspotNetwork
import NetworkExtension

/// Captures the current Wi-Fi SSID if available.
/// Returns nil when:
/// - Device is not connected to Wi-Fi
/// - "Access WiFi Information" entitlement is missing
/// - Location authorization is not precise
/// - App is in restricted background context
private func captureWifiSSID() async -> String? {
    let network = await NEHotspotNetwork.fetchCurrent()
    return network?.ssid
}
```

### Updated logEvent (async conversion)

```swift
// Source: existing ConnectivityMonitor.swift logEvent pattern
private func logEvent(
    type: EventType,
    status: PathStatus,
    interface: InterfaceType,
    isExpensive: Bool,
    isConstrained: Bool,
    probeLatencyMs: Double? = nil,
    probeFailureReason: String? = nil,
    dropDuration: Double? = nil
) {
    // Capture SSID before creating event
    Task {
        let ssid = await captureWifiSSID()
        
        let event = ConnectivityEvent(
            eventType: type,
            pathStatus: status,
            interfaceType: interface,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            radioTechnology: captureRadioTechnology(),
            carrierName: captureCarrierName(),
            probeLatencyMs: probeLatencyMs,
            probeFailureReason: probeFailureReason,
            latitude: lastLocation?.latitude,
            longitude: lastLocation?.longitude,
            locationAccuracy: lastLocation?.accuracy,
            dropDurationSeconds: dropDuration,
            wifiSSID: ssid
        )
        
        try? await eventStore.insertEvent(event)
    }
    
    scheduleDropNotification(eventType: type)
}
```

**Design note:** The existing `logEvent()` already wraps `eventStore.insertEvent()` in a `Task { }`. Adding `await captureWifiSSID()` inside that same Task is natural -- the SSID fetch completes before the event is persisted. The notification scheduling stays outside the Task because it doesn't need the SSID.

### Entitlement Configuration

```xml
<!-- CellGuard/CellGuard.entitlements (new file) -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.wifi-info</key>
    <true/>
</dict>
</plist>
```

The entitlements file must be referenced in the Xcode project build settings under `CODE_SIGN_ENTITLEMENTS`. The easiest way is to add the capability via Xcode's Signing & Capabilities tab, which creates the file and sets the build setting automatically.

### EventDetailView Section (per UI-SPEC)

```swift
// Source: 07-UI-SPEC.md contract
// Insert after Section("Network"), before Section("Cellular")
if event.wifiSSID != nil {
    Section("Wi-Fi") {
        LabeledContent("SSID", value: event.wifiSSID?.isEmpty == true ? "\u{2014}" : event.wifiSSID!)
    }
}
```

### Codable Extension Update

```swift
// Source: existing ConnectivityEvent.swift CodingKeys pattern
enum CodingKeys: String, CodingKey {
    // ... existing keys ...
    case wifiSSID  // NEW
}

// In encode(to:):
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)  // NEW
}

// In init(from:):
// After existing decode calls, add:
// wifiSSID is decoded separately after self.init since it's not in the init params yet
// Use decodeIfPresent for backward compat with pre-Phase-7 exports
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CNCopyCurrentNetworkInfo (SystemConfiguration) | NEHotspotNetwork.fetchCurrent() (NetworkExtension) | iOS 14 (2020) | CNCopy deprecated; returns nil on iOS 26 SDK. Must use NEHotspotNetwork. |
| Completion handler API | `fetchCurrent() async` (Swift concurrency) | iOS 15 / Swift 5.5 | Modern async/await syntax. Use this since CellGuard already uses Swift Concurrency throughout. |
| No location required for SSID | Precise location required | iOS 13 (2019) | Apple added location requirement as privacy measure. CellGuard already has Always + precise auth. |

**Deprecated/outdated:**
- `CNCopyCurrentNetworkInfo`: Deprecated, returns nil on iOS 26 SDK. Do not use.
- `CTCarrier` for network context: Deprecated iOS 16.4 with no replacement. Already handled in codebase (returns nil).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NEHotspotNetwork.fetchCurrent() may return nil in background execution contexts | Pitfall 2 | LOW -- if it works in background, that's strictly better. The nil handling is needed anyway for cellular-only events. |
| A2 | SwiftData automatic lightweight migration handles new optional String? field without VersionedSchema when ModelContainer uses implicit schema | Pattern 2 | MEDIUM -- if migration fails, app crashes on launch. Mitigation: test on device with existing data before shipping. |

## Open Questions

1. **Does NEHotspotNetwork.fetchCurrent() work during background significant-location-change wakes?**
   - What we know: The API requires location authorization (which we have). Apple docs don't explicitly address background execution for this API.
   - What's unclear: Whether iOS restricts SSID access when the app is woken in background by location changes.
   - Recommendation: Implement with nil fallback. Test on physical device: leave app running, let it be woken by movement, check if background-logged events have SSID populated. Either outcome is acceptable.

2. **CSV export does not exist in the codebase -- should Phase 7 create it?**
   - What we know: WIFI-03 says "included in JSON and CSV export." The UI-SPEC specifies CSV column details. But no CSV export code exists anywhere in the project.
   - What's unclear: Whether CSV export was planned for an earlier phase and not built, or whether WIFI-03 is forward-looking.
   - Recommendation: Phase 7 should add `wifiSSID` to the JSON export (which exists) and NOT build CSV export from scratch. CSV is a separate feature that should be its own plan/phase. The requirement text should be interpreted as "when CSV exists, include SSID" -- building an entire export format is out of scope for a field-addition phase.

3. **Should the entitlements file also include other entitlements (e.g., background modes)?**
   - What we know: Background modes are configured in Info.plist (`UIBackgroundModes`), not in the entitlements file. The entitlements file currently does not exist.
   - What's unclear: Whether creating a new entitlements file with only `wifi-info` could conflict with the existing Info.plist-based capability setup.
   - Recommendation: Adding the capability via Xcode Signing & Capabilities tab is the safest approach -- Xcode manages the entitlements file and build settings automatically. Background modes remain in Info.plist (they are not entitlements).

## Sources

### Primary (HIGH confidence)
- [Apple TN3111: iOS Wi-Fi API overview](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview) - Confirmed fetchCurrent() is the current API; CNCopyCurrentNetworkInfo deprecated
- [Apple Developer Documentation: NEHotspotNetwork.fetchCurrent](https://developer.apple.com/documentation/NetworkExtension/NEHotspotNetwork/fetchCurrent(completionHandler:)) - API requirements and entitlement
- [Apple Developer Documentation: Access Wi-Fi Information Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.wifi-info) - Entitlement key `com.apple.developer.networking.wifi-info`
- Context7 /websites/developer_apple - NEHotspotNetwork API surface, entitlement keys, TN3111 content
- Codebase scan - ConnectivityMonitor.swift, ConnectivityEvent.swift, EventDetailView.swift, DashboardView.swift, EventLogExport.swift, LocationService.swift, CellGuardApp.swift

### Secondary (MEDIUM confidence)
- [Hacking with Swift: SwiftData lightweight migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) - Confirmed automatic migration for optional fields
- [Apple Developer Forums: fetchCurrent requirements](https://developer.apple.com/forums/thread/670970) - Four qualification requirements for SSID access
- [Apple Developer Forums: fetchCurrent nil issues](https://developer.apple.com/forums/thread/695418) - Known nil-return scenarios

### Tertiary (LOW confidence)
- Web search results on background SSID capture behavior - Limited authoritative sources on background-specific behavior

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - NEHotspotNetwork is the only supported API. Well-documented with clear requirements.
- Architecture: HIGH - All touchpoints identified from codebase scan. Changes are well-scoped.
- Pitfalls: HIGH - Entitlement and location auth requirements are well-documented. Background behavior is the only uncertain area.
- SwiftData migration: MEDIUM - Automatic migration for optional fields is documented, but project-specific testing needed.

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (stable APIs, no expected changes)
