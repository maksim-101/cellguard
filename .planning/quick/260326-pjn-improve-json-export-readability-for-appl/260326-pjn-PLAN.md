---
phase: quick
plan: 260326-pjn
type: execute
wave: 1
depends_on: []
files_modified:
  - CellGuard/Models/ConnectivityEvent.swift
  - CellGuard/Models/EventLogExport.swift
autonomous: true
must_haves:
  truths:
    - "JSON export encodes EventType as human-readable strings like 'pathChange', not integers like 0"
    - "JSON export encodes PathStatus and InterfaceType as human-readable strings, not integers"
    - "JSON export wraps events in a top-level object with device/OS metadata"
    - "Privacy toggle still strips location fields when enabled"
  artifacts:
    - path: "CellGuard/Models/ConnectivityEvent.swift"
      provides: "String-based enum encoding for JSON export"
      contains: "encodingString"
    - path: "CellGuard/Models/EventLogExport.swift"
      provides: "Top-level metadata wrapper with device info and events array"
      contains: "CellGuardExport"
  key_links:
    - from: "CellGuard/Models/ConnectivityEvent.swift"
      to: "CellGuard/Models/EventLogExport.swift"
      via: "encode(to:) produces string enums consumed by EventLogExport wrapper"
    - from: "CellGuard/Models/EventLogExport.swift"
      to: "CellGuard/Views/DashboardView.swift"
      via: "ShareLink item -- existing ShareLink unchanged, EventLogExport now encodes wrapper"
---

<objective>
Improve JSON export readability so Apple Feedback Assistant engineers can understand the data without a codebook.

Purpose: Raw integer enum values (0, 1, 2...) in the current JSON output are meaningless to anyone reading the export. Wrapping events in a metadata envelope provides immediate context about the device, OS, collection period, and event counts.

Output: Updated ConnectivityEvent.swift with string-based enum encoding for JSON, and updated EventLogExport.swift that produces a top-level `{ metadata: {...}, events: [...] }` structure.
</objective>

<execution_context>
@~/.claude/get-shit-done/workflows/execute-plan.md
@~/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CellGuard/Models/ConnectivityEvent.swift
@CellGuard/Models/EventLogExport.swift
@CellGuard/Views/DashboardView.swift
@CellGuard/Helpers/DropClassification.swift

<interfaces>
<!-- From ConnectivityEvent.swift -- current encode(to:) already uses CodingUserInfoKey.omitLocation -->
```swift
extension CodingUserInfoKey {
    static let omitLocation = CodingUserInfoKey(rawValue: "omitLocation")!
}

enum EventType: Int, Codable, CaseIterable {
    case pathChange = 0, silentFailure = 1, probeSuccess = 2,
         probeFailure = 3, connectivityRestored = 4, monitoringGap = 5
}
enum PathStatus: Int, Codable {
    case satisfied = 0, unsatisfied = 1, requiresConnection = 2
}
enum InterfaceType: Int, Codable {
    case cellular = 0, wifi = 1, wiredEthernet = 2, loopback = 3, other = 4, unknown = 5
}
```

<!-- From EventLogExport.swift -- current structure encodes [ConnectivityEvent] directly -->
```swift
struct EventLogExport: Transferable {
    let events: [ConnectivityEvent]
    let omitLocation: Bool
    // transferRepresentation encodes export.events as top-level JSON array
}
```

<!-- From DashboardView.swift -- ShareLink usage (must remain compatible) -->
```swift
ShareLink(
    item: EventLogExport(events: allEvents, omitLocation: omitLocation),
    preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text"))
)
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add string encoding to enums and update encode(to:)</name>
  <files>CellGuard/Models/ConnectivityEvent.swift</files>
  <action>
Add an `encodingString` computed property to each of the three enums (EventType, PathStatus, InterfaceType) that returns a camelCase string representation suitable for JSON. These are NOT the displayName strings (which are title-cased for UI) -- they are stable, machine-friendly identifiers:

EventType: "pathChange", "silentFailure", "probeSuccess", "probeFailure", "connectivityRestored", "monitoringGap"
PathStatus: "satisfied", "unsatisfied", "requiresConnection"
InterfaceType: "cellular", "wifi", "wiredEthernet", "loopback", "other", "unknown"

Update the `encode(to:)` method in the Codable extension to encode these three fields as their `encodingString` values instead of the enum's default Int-based Codable encoding. Specifically, replace:
```swift
try container.encode(eventType, forKey: .eventType)
try container.encode(pathStatus, forKey: .pathStatus)
try container.encode(interfaceType, forKey: .interfaceType)
```
with:
```swift
try container.encode(eventType.encodingString, forKey: .eventType)
try container.encode(pathStatus.encodingString, forKey: .pathStatus)
try container.encode(interfaceType.encodingString, forKey: .interfaceType)
```

Update `init(from decoder:)` to handle string-based decoding: try decoding as String first (mapping back via a static `fromEncodingString` method or by trying each case), fall back to Int-based decoding for backwards compatibility with any previously exported files.

Do NOT change the enum raw value type from Int -- SwiftData predicates depend on the Int raw values. The string encoding is only for the Codable JSON path.
  </action>
  <verify>
    <automated>cd /Users/mowehr/Documents/claude_projects/cellguard && xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -5</automated>
  </verify>
  <done>All three enums encode as human-readable strings in JSON. Decoding handles both string (new) and int (legacy) formats. Project compiles without errors.</done>
</task>

<task type="auto">
  <name>Task 2: Wrap export in metadata envelope</name>
  <files>CellGuard/Models/EventLogExport.swift</files>
  <action>
Replace the current EventLogExport implementation that encodes a bare `[ConnectivityEvent]` array with a top-level wrapper structure. The JSON output should look like:

```json
{
  "metadata": {
    "appName": "CellGuard",
    "appVersion": "1.1",
    "buildNumber": "...",
    "deviceModel": "iPhone17,4",
    "osVersion": "iOS 26.0",
    "carrier": "Swisscom" or null,
    "collectionPeriod": {
      "start": "2026-03-20T...",
      "end": "2026-03-26T..."
    },
    "totalEvents": 1234,
    "totalDrops": 42,
    "exportDate": "2026-03-26T...",
    "locationDataIncluded": true
  },
  "events": [ ... ]
}
```

Implementation approach:
1. Create a private `CellGuardExport` Codable struct with `metadata` and `events` fields.
2. Create a private `ExportMetadata` Codable struct for the metadata fields.
3. Gather device info using `UIDevice.current.model`, `UIDevice.current.systemName`, `UIDevice.current.systemVersion`, and `Bundle.main.infoDictionary` for app version/build.
4. For carrier: use `CTTelephonyNetworkInfo().serviceSubscriberCellularProviders?.values.first?.carrierName` (import CoreTelephony). Handle nil gracefully.
5. For collection period: derive from first/last event timestamps (events are already sorted by caller, but sort defensively).
6. For totalDrops: use `isDropEvent()` from DropClassification.swift to count drops consistently.
7. For `locationDataIncluded`: use the inverse of `omitLocation`.
8. In the transferRepresentation, encode `CellGuardExport(metadata:events:)` instead of `export.events`.
9. Pass the same `omitLocation` userInfo to the encoder so ConnectivityEvent's `encode(to:)` still strips location fields.

Keep the existing `EventLogExport` struct interface identical (same init, same Transferable conformance) so DashboardView's ShareLink does not need changes.
  </action>
  <verify>
    <automated>cd /Users/mowehr/Documents/claude_projects/cellguard && xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -5</automated>
  </verify>
  <done>JSON export produces a top-level object with metadata (device, OS, carrier, app version, collection period, counts) and events array. Privacy toggle still controls location omission. DashboardView ShareLink unchanged.</done>
</task>

</tasks>

<verification>
Build succeeds: `xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`
</verification>

<success_criteria>
- JSON export contains human-readable enum strings ("pathChange", "satisfied", "cellular") instead of raw integers (0, 1, 2)
- JSON export is wrapped in `{ "metadata": {...}, "events": [...] }` structure
- Metadata includes: appName, appVersion, buildNumber, deviceModel, osVersion, carrier, collectionPeriod, totalEvents, totalDrops, exportDate, locationDataIncluded
- Privacy toggle (omitLocation) still strips latitude/longitude/locationAccuracy from events and sets locationDataIncluded to false in metadata
- No changes to DashboardView or any other view files
- Project compiles cleanly
</success_criteria>

<output>
After completion, create `.planning/quick/260326-pjn-improve-json-export-readability-for-appl/260326-pjn-SUMMARY.md`
</output>
