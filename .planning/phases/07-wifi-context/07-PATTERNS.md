# Phase 7: Wi-Fi Context - Pattern Map

**Mapped:** 2026-04-20
**Files analyzed:** 5 (4 modified, 1 new)
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `CellGuard/Models/ConnectivityEvent.swift` | model | CRUD | self (existing field pattern) | exact |
| `CellGuard/Services/ConnectivityMonitor.swift` | service | event-driven | self (`captureRadioTechnology()` pattern) | exact |
| `CellGuard/Views/EventDetailView.swift` | component | request-response | self (conditional Section pattern) | exact |
| `CellGuard/Models/EventLogExport.swift` | model | transform | self (privacy-gated encode pattern) | exact |
| `CellGuard/Views/DashboardView.swift` | component | request-response | self (Toggle label at line 97) | exact |
| `CellGuard/CellGuard.entitlements` | config | N/A | none (new file) | N/A |

**Note:** All five code files are modifications to existing files. Each file is its own best analog -- the new `wifiSSID` field follows the exact same pattern as existing fields in every layer. The entitlements file is the only truly new file and has no analog in the codebase.

## Pattern Assignments

### `CellGuard/Models/ConnectivityEvent.swift` (model, CRUD)

**Analog:** self -- follow the pattern of existing optional `String?` fields like `radioTechnology` and `carrierName`.

**Property declaration pattern** (lines 80-84):
```swift
// MARK: Cellular metadata

/// Radio access technology string, e.g. "CTRadioAccessTechnologyNR" for 5G. Nil if unknown.
var radioTechnology: String?

/// Carrier name from CTTelephonyNetworkInfo. May be nil due to CTCarrier deprecation on iOS 16.4+.
var carrierName: String?
```
New `wifiSSID: String?` goes in a new `// MARK: Wi-Fi metadata` section after the Cellular metadata block (after line 84), before the Active probe results section. Comment style matches: `/// Wi-Fi SSID at the time of the event. Nil if not connected to Wi-Fi or SSID could not be captured.`

**Init parameter pattern** (lines 140-171):
```swift
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
    // ...
    self.radioTechnology = radioTechnology
    self.carrierName = carrierName
    // ...
}
```
Add `wifiSSID: String? = nil` parameter after `carrierName` in the init signature. Add `self.wifiSSID = wifiSSID` in the body after `self.carrierName = carrierName`.

**CodingKeys pattern** (lines 178-194):
```swift
enum CodingKeys: String, CodingKey {
    case timestamp
    case timestampUTC
    case eventType
    case pathStatus
    case interfaceType
    case isExpensive
    case isConstrained
    case radioTechnology
    case carrierName
    case probeLatencyMs
    case probeFailureReason
    case latitude
    case longitude
    case locationAccuracy
    case dropDurationSeconds
}
```
Add `case wifiSSID` after `locationAccuracy` (keeping privacy-sensitive fields adjacent).

**Encode pattern -- privacy gate** (lines 258-264):
```swift
let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
}
```
Add `try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)` inside the `if !omitLocation` block, after `locationAccuracy`.

**Decode pattern** (lines 236-241):
```swift
radioTechnology: try container.decodeIfPresent(String.self, forKey: .radioTechnology),
carrierName: try container.decodeIfPresent(String.self, forKey: .carrierName),
```
The init(from:) convenience initializer passes all fields through `self.init(...)`. Add `wifiSSID` to the init call: `wifiSSID: try container.decodeIfPresent(String.self, forKey: .wifiSSID)`. Use `decodeIfPresent` for backward compatibility with pre-Phase-7 JSON exports.

---

### `CellGuard/Services/ConnectivityMonitor.swift` (service, event-driven)

**Analog:** self -- the `captureRadioTechnology()` helper at lines 337-340 is the exact pattern for the new `captureWifiSSID()` helper.

**Import pattern** (lines 1-5):
```swift
import Network
import Observation
import Foundation
import CoreTelephony
import UserNotifications
```
Add `import NetworkExtension` to this block.

**Capture helper pattern** (lines 337-346):
```swift
/// Captures the current radio access technology string for event metadata (MON-04).
/// Returns values like "CTRadioAccessTechnologyLTE", "CTRadioAccessTechnologyNR", etc.
private func captureRadioTechnology() -> String? {
    let freshInfo = CTTelephonyNetworkInfo()
    return freshInfo.serviceCurrentRadioAccessTechnology?.values.first
}

/// Carrier name is no longer available -- Apple deprecated CTCarrier in iOS 16 with no replacement.
private func captureCarrierName() -> String? {
    nil
}
```
Add a new `captureWifiSSID()` method in the same section, after `captureCarrierName()`. It must be `async` (unlike the sync radio/carrier captures) because `NEHotspotNetwork.fetchCurrent()` is async:
```swift
/// Captures the current Wi-Fi SSID if available.
/// Returns nil when not on Wi-Fi, missing entitlement, or in restricted background context.
private func captureWifiSSID() async -> String? {
    let network = await NEHotspotNetwork.fetchCurrent()
    return network?.ssid
}
```

**logEvent pattern** (lines 491-522):
```swift
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
        dropDurationSeconds: dropDuration
    )

    Task {
        try? await eventStore.insertEvent(event)
    }

    scheduleDropNotification(eventType: type)
}
```
The SSID capture is async, so `captureWifiSSID()` must be `await`ed. The existing `logEvent()` already wraps persistence in `Task { }`. The SSID fetch must happen inside that Task (before event creation) so the captured value is stored atomically with the event. Move event creation inside the existing Task block:
```swift
Task {
    let ssid = await captureWifiSSID()
    let event = ConnectivityEvent(
        // ... all existing params ...
        wifiSSID: ssid
    )
    try? await eventStore.insertEvent(event)
}
```
The `scheduleDropNotification(eventType: type)` call stays outside the Task since it does not need the SSID.

---

### `CellGuard/Views/EventDetailView.swift` (component, request-response)

**Analog:** self -- the conditional Section pattern at lines 30-39 (Probe) and lines 41-53 (Location).

**Conditional Section pattern** (lines 41-53):
```swift
if event.latitude != nil {
    Section("Location") {
        if let lat = event.latitude {
            LabeledContent("Latitude", value: String(format: "%.4f", lat))
        }
        if let lon = event.longitude {
            LabeledContent("Longitude", value: String(format: "%.4f", lon))
        }
        if let accuracy = event.locationAccuracy {
            LabeledContent("Accuracy", value: String(format: "%.0f m", accuracy))
        }
    }
}
```

**Non-conditional Section pattern** (lines 25-29):
```swift
Section("Cellular") {
    LabeledContent("Radio Tech", value: radioTechDisplay)
    LabeledContent("Carrier", value: event.carrierName ?? "Unknown")
}
```

New Wi-Fi section goes **after** `Section("Cellular")` (line 29) and **before** the probe section (line 30). Per UI-SPEC, the section order is: Event, Network, Wi-Fi, Cellular, Probe, Location, Duration.

**Correction:** UI-SPEC says Wi-Fi goes after Cellular, before Probe. Looking at the current order: Event (line 13), Network (line 18), Cellular (line 25), Probe (line 30), Location (line 41), Duration (line 55). The new Wi-Fi section inserts between Cellular and Probe:
```swift
if event.wifiSSID != nil {
    Section("Wi-Fi") {
        LabeledContent("SSID", value: event.wifiSSID?.isEmpty == true ? "\u{2014}" : event.wifiSSID!)
    }
}
```
This follows the conditional Section pattern from Location (line 41). The nil guard hides the entire section when the device was on cellular only.

---

### `CellGuard/Models/EventLogExport.swift` (model, transform)

**Analog:** self -- the `EventLogExport` struct and its `transferRepresentation` at lines 45-99.

**No code changes needed in this file.** The export encoding is driven entirely by `ConnectivityEvent.encode(to:)` in `ConnectivityEvent.swift`. When `wifiSSID` is added to the CodingKeys and encode method there, EventLogExport automatically includes it in the JSON output. The `omitLocation` userInfo flag is already set at line 56-58:
```swift
if export.omitLocation {
    encoder.userInfo[.omitLocation] = true
}
```
This same flag gates `wifiSSID` in the encode method (see ConnectivityEvent pattern above). No changes to `ExportMetadata` or `EventLogExport` are needed.

---

### `CellGuard/Views/DashboardView.swift` (component, request-response)

**Analog:** self -- the privacy Toggle at line 97.

**Toggle label pattern** (lines 97-103):
```swift
// Privacy toggle for export (EXPT-01, EXPT-03)
Toggle("Omit location data", isOn: $omitLocation)
    .font(.subheadline)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
```
Change the label string from `"Omit location data"` to `"Omit location and Wi-Fi data"` per UI-SPEC. No logic change -- the `omitLocation` AppStorage key continues to drive both location and SSID redaction.

---

### `CellGuard/CellGuard.entitlements` (config, N/A)

**No analog** -- no entitlements file exists in the codebase. This is a new plist file.

**Content:**
```xml
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

**Xcode project integration:** The `CODE_SIGN_ENTITLEMENTS` build setting in `CellGuard.xcodeproj/project.pbxproj` must reference `CellGuard/CellGuard.entitlements`. The safest approach is adding the "Access WiFi Information" capability via Xcode's Signing & Capabilities tab, which creates the file and sets the build setting automatically. If done manually, the entitlements file must be at `CellGuard/CellGuard.entitlements` (same directory as `Info.plist`).

---

## Shared Patterns

### Privacy Gate (omitLocation)
**Source:** `CellGuard/Models/ConnectivityEvent.swift` lines 5-9, 258-263
**Apply to:** ConnectivityEvent.swift (encode method) and DashboardView.swift (toggle label)

The `omitLocation` pattern is the single cross-cutting concern in this phase. It works via encoder userInfo:
```swift
// Definition (ConnectivityEvent.swift line 5-9)
extension CodingUserInfoKey {
    static let omitLocation = CodingUserInfoKey(rawValue: "omitLocation")!
}

// Usage in encode (ConnectivityEvent.swift lines 258-263)
let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    // NEW: try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)
}

// Set by EventLogExport (EventLogExport.swift lines 56-58)
if export.omitLocation {
    encoder.userInfo[.omitLocation] = true
}

// Driven by UI (DashboardView.swift line 15)
@AppStorage("omitLocationData") private var omitLocation = false
```
SSID piggybacks on this existing mechanism. No new flag or key is needed.

### Optional Field + decodeIfPresent (backward compat)
**Source:** `CellGuard/Models/ConnectivityEvent.swift` lines 232-239
**Apply to:** ConnectivityEvent.swift (decode method)

All optional fields use `decodeIfPresent` for backward compatibility with older exports:
```swift
radioTechnology: try container.decodeIfPresent(String.self, forKey: .radioTechnology),
carrierName: try container.decodeIfPresent(String.self, forKey: .carrierName),
```
The new `wifiSSID` field must follow the same pattern so pre-Phase-7 JSON files can still be imported without error.

### Conditional Section in Detail View
**Source:** `CellGuard/Views/EventDetailView.swift` lines 41-53
**Apply to:** EventDetailView.swift (new Wi-Fi section)

The pattern for showing/hiding sections based on optional data:
```swift
if event.latitude != nil {
    Section("Location") {
        // rows
    }
}
```
Wi-Fi section uses the same guard: `if event.wifiSSID != nil { Section("Wi-Fi") { ... } }`.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `CellGuard/CellGuard.entitlements` | config | N/A | No entitlements file exists in the project. Use the standard Apple plist format from RESEARCH.md. |

**Note:** CSV export is mentioned in WIFI-03 and the UI-SPEC but no CSV export code exists anywhere in the codebase. Per RESEARCH.md open question #2, CSV export is out of scope for Phase 7 -- the `wifiSSID` field will only be added to the existing JSON export. CSV export should be a separate phase.

---

## Metadata

**Analog search scope:** `CellGuard/` (all 18 Swift source files)
**Files scanned:** 18
**Pattern extraction date:** 2026-04-20
