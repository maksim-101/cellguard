# Phase 5: Privacy-Aware Export - Research

**Researched:** 2026-03-26
**Domain:** SwiftUI export privacy, Codable conditional encoding, UserDefaults persistence
**Confidence:** HIGH

## Summary

Phase 5 adds a single privacy toggle ("Omit location data") to the existing JSON export flow. The current `EventLogExport` struct encodes all `ConnectivityEvent` fields including `latitude`, `longitude`, and `locationAccuracy`. The toggle must strip these three fields from the JSON output when enabled, and persist the user's choice across app launches.

The implementation is well-scoped: modify `EventLogExport` to accept an `omitLocation` flag, conditionally skip location fields in the custom `encode(to:)` method, add a `Toggle` to `DashboardView` above the existing `ShareLink`, and persist the toggle state with `@AppStorage`. No new frameworks, dependencies, or architectural changes are required.

**Primary recommendation:** Add an `omitLocation` parameter to `EventLogExport`, use `userInfo` on the `JSONEncoder` to pass it to `ConnectivityEvent.encode(to:)`, and persist the toggle with `@AppStorage("omitLocationData")`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXPT-01 | User can toggle "Omit location data" before exporting JSON | SwiftUI `Toggle` bound to `@AppStorage` in DashboardView, positioned above the existing ShareLink |
| EXPT-02 | When privacy toggle is on, exported JSON excludes latitude and longitude fields from all events | Conditional encoding in `ConnectivityEvent.encode(to:)` using encoder `userInfo` dictionary to pass the omit flag |
| EXPT-03 | Privacy toggle state persists across app launches | `@AppStorage("omitLocationData")` wrapping `UserDefaults.standard` -- automatic persistence, no extra code needed |
</phase_requirements>

## Standard Stack

### Core (already in project -- no new dependencies)

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| `@AppStorage` | iOS 14+ (SwiftUI) | Persist toggle state | Built-in SwiftUI property wrapper over UserDefaults. One line of code for persistence. |
| `JSONEncoder.userInfo` | Foundation | Pass omit flag to encoder | Standard Codable pattern for passing context to `encode(to:)` without changing the model signature. |
| SwiftUI `Toggle` | iOS 13+ | Privacy toggle UI | Native SwiftUI control. |

### No new dependencies needed

This phase requires zero new libraries. Everything is built on Foundation Codable and SwiftUI primitives already in use.

## Architecture Patterns

### Pattern 1: Encoder userInfo for conditional encoding

**What:** Pass runtime context (the omit flag) to `encode(to:)` via `JSONEncoder.userInfo`, a `[CodingUserInfoKey: Any]` dictionary. This avoids modifying the `ConnectivityEvent` model or creating a parallel DTO.

**When to use:** When the same model needs different encoding behavior based on runtime context.

**Example:**
```swift
// Define a CodingUserInfoKey
extension CodingUserInfoKey {
    static let omitLocation = CodingUserInfoKey(rawValue: "omitLocation")!
}

// In EventLogExport, set it on the encoder:
let encoder = JSONEncoder()
if omitLocation {
    encoder.userInfo[.omitLocation] = true
}
let data = try encoder.encode(export.events)

// In ConnectivityEvent.encode(to:), check it:
func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // ... encode other fields ...

    let omit = encoder.userInfo[.omitLocation] as? Bool ?? false
    if !omit {
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    }
}
```

### Pattern 2: @AppStorage for toggle persistence (EXPT-03)

**What:** `@AppStorage("omitLocationData")` provides a `Bool` binding that auto-persists to `UserDefaults.standard`.

**When to use:** Simple key-value persistence for user preferences.

**Example:**
```swift
@AppStorage("omitLocationData") private var omitLocation = false

Toggle("Omit location data", isOn: $omitLocation)
```

### Pattern 3: EventLogExport accepts privacy flag

**What:** Modify `EventLogExport` to take an `omitLocation: Bool` parameter and pass it through to the encoder.

**Example:**
```swift
struct EventLogExport: Transferable {
    let events: [ConnectivityEvent]
    let omitLocation: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if export.omitLocation {
                encoder.userInfo[.omitLocation] = true
            }
            let data = try encoder.encode(export.events)
            // ... file writing unchanged ...
        }
    }
}
```

### Anti-Patterns to Avoid

- **Creating a separate PrivateConnectivityEvent struct:** Duplicates the model. The userInfo approach keeps one model with conditional encoding.
- **Filtering fields after encoding:** Parsing JSON to remove keys is fragile and wasteful. Control encoding at the source.
- **Using a global/static flag:** Thread-unsafe. Pass the flag through the encoder's userInfo dictionary instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toggle persistence | Manual UserDefaults read/write with didSet | `@AppStorage` | One-liner, auto-syncs with SwiftUI view lifecycle |
| Conditional JSON fields | Post-processing JSON string to strip keys | `encoder.userInfo` + conditional `encodeIfPresent` | Type-safe, no string manipulation, impossible to miss a field |

## Common Pitfalls

### Pitfall 1: ShareLink re-renders on toggle change

**What goes wrong:** If the `ShareLink` item is recomputed every time the toggle changes, it may cause unnecessary re-renders or stale state.
**Why it happens:** `ShareLink` captures its item at render time. When `@AppStorage` changes, the view re-renders and `ShareLink` gets the new `EventLogExport` with the updated flag.
**How to avoid:** This is actually correct behavior -- SwiftUI's declarative model handles this naturally. The `ShareLink` will use whatever `omitLocation` value is current when the user taps it. No caching issue.

### Pitfall 2: Forgetting locationAccuracy

**What goes wrong:** Stripping latitude and longitude but leaving `locationAccuracy` in the JSON. A horizontal accuracy of 50m at a specific timestamp could narrow down location when cross-referenced.
**Why it happens:** locationAccuracy seems harmless but combined with timestamps could theoretically aid de-anonymization.
**How to avoid:** Strip all three location fields: `latitude`, `longitude`, and `locationAccuracy`.

### Pitfall 3: Toggle default should be privacy-preserving

**What goes wrong:** Defaulting to `false` (location included) means users who don't notice the toggle will share location data.
**Why it happens:** Developer convenience -- `false` is the natural default for a Bool.
**How to avoid:** The requirements say "toggle remembers last choice" but don't specify default. Defaulting to `false` (off = include location) matches the existing behavior where exports always include location. This is the correct default since users have already granted location permission to the app.

## Code Examples

### Current export flow (what exists today)

In `DashboardView.swift` (lines 96-111):
```swift
ShareLink(
    item: EventLogExport(events: allEvents),
    preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text"))
) { ... }
```

In `EventLogExport.swift`: `Transferable` struct that encodes all events to JSON.

In `ConnectivityEvent.swift` (lines 229-233): Custom `encode(to:)` that encodes latitude, longitude, locationAccuracy via `encodeIfPresent`.

### Target state after this phase

DashboardView gains a toggle above the ShareLink:
```swift
@AppStorage("omitLocationData") private var omitLocation = false

// In body, above the ShareLink:
Toggle("Omit location data", isOn: $omitLocation)

// ShareLink passes the flag:
ShareLink(
    item: EventLogExport(events: allEvents, omitLocation: omitLocation),
    preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text"))
) { ... }
```

## Open Questions

None. This phase is fully scoped with no ambiguity.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `EventLogExport.swift`, `ConnectivityEvent.swift`, `DashboardView.swift`
- Apple Developer Documentation: `CodingUserInfoKey`, `JSONEncoder.userInfo`, `@AppStorage`

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all built-in Apple frameworks already in use
- Architecture: HIGH - userInfo pattern is standard Codable, @AppStorage is standard SwiftUI
- Pitfalls: HIGH - straightforward feature with well-understood risks

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable APIs, no moving parts)
