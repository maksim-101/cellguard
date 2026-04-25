# Phase 8: VPN Context — Pattern Map

**Mapped:** 2026-04-25
**Files analyzed:** 4 modified, 0 created
**Analogs found:** 4 / 4 (all analogs in-tree from Phase 7 work)

> Phase 8 is a near-mirror of Phase 7 (Wi-Fi Context). Every new code site has a
> Phase-7-shipped analog in the same file, often within 5–10 lines of where the
> new code lands. The dominant rule for the planner: **copy Phase 7's wifiSSID
> work, substituting `vpnState` and `VPNState`.**

---

## File Classification

| Modified File | Role | Data Flow | Closest Analog (in-tree) | Match Quality |
|--------------|------|-----------|-------------------------|---------------|
| `CellGuard/Models/ConnectivityEvent.swift` | model | transform (encode/decode + enum) | self (Phase 7 `wifiSSID` field + `InterfaceType` enum) | exact |
| `CellGuard/Services/ConnectivityMonitor.swift` | service | event-driven (path updates, probe) | self (Phase 7 `captureWifiSSID` + Phase 6 race-safety in `runProbe`) | exact |
| `CellGuard/Views/EventDetailView.swift` | component | request-response (read-only render) | self (`Section("Wi-Fi")` block at lines 30-34) | exact |
| `CellGuard/Views/DashboardView.swift` | component | request-response (live `@Observable` binding + toggle) | self (`Text(monitor.currentInterfaceType.displayName)` line 180; privacy toggle line 97) | exact |

**Privacy redaction site (clarification on RESEARCH.md):** `EventLogExport.swift`
does **not** need code changes. The `omitLocation` userInfo flag plumbing at
`EventLogExport.swift:56-57` is already correct and generic — it sets the encoder
flag, and `ConnectivityEvent.encode(to:)` does the actual field stripping at
lines 267-273. Adding `vpnState` to the existing `if !omitLocation { ... }` block
in `ConnectivityEvent.swift` is the **only** redaction site that changes.
RESEARCH.md got this right (line 362: "EventLogExport.swift — No code changes").

The privacy **toggle label** copy change ("Omit location and Wi-Fi data" →
"Omit location, Wi-Fi, and VPN data") lives at `DashboardView.swift:97` and is
already in the modified-files list.

---

## Pattern Assignments

### `CellGuard/Models/ConnectivityEvent.swift` (model, transform)

**Analog:** self — Phase 7's `wifiSSID` field and the existing `InterfaceType`
enum implementation are the line-for-line template.

#### Pattern 1: Enum shape (Int rawValue + encodingString + fromEncodingString + displayName)

**Source:** `ConnectivityEvent.swift:31-38, 328-353` (`InterfaceType` is the closest analog because it has 6 cases like NEVPNStatus has 6 states).

**Rawvalue declaration** (lines 31-38):
```swift
/// Network interface type for the active path.
enum InterfaceType: Int, Codable {
    case cellular = 0
    case wifi = 1
    case wiredEthernet = 2
    case loopback = 3
    case other = 4
    case unknown = 5
}
```
> Copy this shape for `VPNState`. Use **explicit raw values** (D-03; see comment at line 11: "never rely on auto-increment — migration safety"). Order per UI-SPEC: `.invalid = 0, .disconnected = 1, .connecting = 2, .connected = 3, .reasserting = 4, .disconnecting = 5`.

**`encodingString` + `fromEncodingString` extension** (lines 328-353):
```swift
extension InterfaceType {
    /// Stable camelCase identifier for JSON export.
    var encodingString: String {
        switch self {
        case .cellular: "cellular"
        case .wifi: "wifi"
        case .wiredEthernet: "wiredEthernet"
        case .loopback: "loopback"
        case .other: "other"
        case .unknown: "unknown"
        }
    }

    static func fromEncodingString(_ string: String) -> InterfaceType? {
        switch string {
        case "cellular": .cellular
        case "wifi": .wifi
        case "wiredEthernet": .wiredEthernet
        case "loopback": .loopback
        case "other": .other
        case "unknown": .unknown
        default: nil
        }
    }
}
```
> Copy verbatim, replacing case names. Encoding strings come from UI-SPEC table (lines 264-273): `invalid`, `disconnected`, `connecting`, `connected`, `reasserting`, `disconnecting` (all lowercase camelCase, matching the literal NEVPNStatus enum names lowercased).

**`displayName` extension lives in `EventDetailView.swift`** (lines 110-122) — the existing project convention places UI-only display strings with the view file, not the model file. **Phase 8 must follow this convention** and put `VPNState.displayName` in `EventDetailView.swift` alongside `InterfaceType.displayName` and `PathStatus.displayName`. UI-SPEC display strings (table at line 112-119): `Invalid`, `Disconnected`, `Connecting`, `Connected`, `Reconnecting` (NOT "Reasserting"), `Disconnecting`.

#### Pattern 2: Optional storage property + computed enum accessor

**Source:** `ConnectivityEvent.swift:67-68, 130-133` (the `interfaceTypeRaw: Int` + `interfaceType: InterfaceType` computed pair).

```swift
// Storage (line 67-68)
/// Raw integer storage for InterfaceType enum. Use `interfaceType` computed property for typed access.
var interfaceTypeRaw: Int

// Computed accessor (lines 130-133)
var interfaceType: InterfaceType {
    get { InterfaceType(rawValue: interfaceTypeRaw) ?? .unknown }
    set { interfaceTypeRaw = newValue.rawValue }
}
```
> **Difference for VPN:** the storage type must be `Int?` (optional), not `Int`, because legacy events (pre-Phase 8) have no VPN state recorded. The accessor returns `VPNState?`:
> ```swift
> var vpnStateRaw: Int?
>
> var vpnState: VPNState? {
>     get { vpnStateRaw.flatMap(VPNState.init(rawValue:)) }
>     set { vpnStateRaw = newValue?.rawValue }
> }
> ```
> This is the same shape as Phase 7's `wifiSSID: String?` (line 89) — additive optional, no SwiftData migration needed (RESEARCH.md confirms at line 350).

#### Pattern 3: Init parameter ordering

**Source:** `ConnectivityEvent.swift:145-178` — the canonical init.

Phase 7's `wifiSSID: String? = nil` parameter is at line 154, between `carrierName` and `probeLatencyMs`. Phase 8 should add `vpnState: VPNState? = nil` **immediately after `wifiSSID`** (per RESEARCH.md line 326), keeping the privacy-sensitive cluster contiguous.

```swift
// Existing block to extend (lines 152-160):
radioTechnology: String? = nil,
carrierName: String? = nil,
wifiSSID: String? = nil,
// vpnState: VPNState? = nil,   ← ADD HERE
probeLatencyMs: Double? = nil,
probeFailureReason: String? = nil,
```

#### Pattern 4: Decode block with String-first / Int-fallback

**Source:** `ConnectivityEvent.swift:225-231` — `interfaceType` decoder.

```swift
let interfaceType: InterfaceType
if let str = try? container.decode(String.self, forKey: .interfaceType),
   let decoded = InterfaceType.fromEncodingString(str) {
    interfaceType = decoded
} else {
    interfaceType = try container.decode(InterfaceType.self, forKey: .interfaceType)
}
```
> Copy this exact shape. **Difference for VPN:** the field is optional, so use `decodeIfPresent` (analog: line 242 `wifiSSID: try container.decodeIfPresent(String.self, forKey: .wifiSSID)`). RESEARCH.md spells it out at lines 335-343:
> ```swift
> let vpnState: VPNState?
> if let str = try? container.decodeIfPresent(String.self, forKey: .vpnState) {
>     vpnState = str.flatMap(VPNState.fromEncodingString)
> } else if let raw = try? container.decodeIfPresent(Int.self, forKey: .vpnState) {
>     vpnState = VPNState(rawValue: raw)
> } else {
>     vpnState = nil
> }
> ```

#### Pattern 5: Privacy-gated encode block (THE redaction site)

**Source:** `ConnectivityEvent.swift:267-273` — the existing `omitLocation` block.

```swift
let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)
}
```
> **This is the single redaction site for Phase 8.** Add `vpnState` here, but with the UI-SPEC export-filter exception (do not encode `.disconnected` or `.invalid`):
> ```swift
> if !omitLocation {
>     // ...existing four lines...
>     if let state = vpnState, state != .disconnected, state != .invalid {
>         try container.encode(state.encodingString, forKey: .vpnState)
>     }
> }
> ```
> Why the extra filter (UI-SPEC §Export — JSON, lines 252-254): consumers scanning JSON for VPN context want the key to be **present because** a tunnel was active or transitioning, not present-but-disconnected on every row. This is the same "absence communicates absence" principle Phase 7 established for the detail view.

#### Pattern 6: CodingKey ordering

**Source:** `ConnectivityEvent.swift:185-202` — the CodingKeys enum.

Phase 7's `case wifiSSID` is at line 200 (after `locationAccuracy`, before `dropDurationSeconds`). Phase 8 adds `case vpnState` immediately after `wifiSSID`:

```swift
case latitude
case longitude
case locationAccuracy
case wifiSSID
// case vpnState   ← ADD HERE
case dropDurationSeconds
```

---

### `CellGuard/Services/ConnectivityMonitor.swift` (service, event-driven)

**Analog:** self — three Phase 7 / Phase 6 patterns combine here.

#### Pattern 1: Synchronous metadata capture **outside** the Task block (D-09)

**Source:** `ConnectivityMonitor.swift:509-535` — the `logEvent` body.

```swift
// Capture synchronous metadata outside the Task
let radioTech = captureRadioTechnology()
let carrier = captureCarrierName()
let location = lastLocation

Task {
    let ssid = await captureWifiSSID()

    let event = ConnectivityEvent(
        eventType: type,
        pathStatus: status,
        interfaceType: interface,
        isExpensive: isExpensive,
        isConstrained: isConstrained,
        radioTechnology: radioTech,
        carrierName: carrier,
        wifiSSID: ssid,
        probeLatencyMs: probeLatencyMs,
        probeFailureReason: probeFailureReason,
        latitude: location?.latitude,
        longitude: location?.longitude,
        locationAccuracy: location?.accuracy,
        dropDurationSeconds: dropDuration
    )

    try? await eventStore.insertEvent(event)
}
```
> **Phase 8 addition:** add `let vpnState = captureVPNState()` to the synchronous capture block (line 512 area), thread `vpnState: vpnState` into the `ConnectivityEvent(...)` initializer call, and add a `vpnState: VPNState? = nil` parameter to `logEvent`'s signature (lines 499-508). Capture site is **outside** the Task because `CFNetworkCopySystemProxySettings()` is synchronous (RESEARCH.md lines 217-227).

#### Pattern 2: Race-safe state snapshot in `runProbe()`

**Source:** `ConnectivityMonitor.swift:227-229` — pre-await snapshot.

```swift
@MainActor
private func runProbe() async {
    // Pitfall 5: Capture state before awaiting probe to avoid race condition
    let capturedStatus = currentPathStatus
    let capturedInterface = currentInterfaceType

    var request = URLRequest(url: probeURL)
    request.httpMethod = "HEAD"
    // ...
}
```
> **Phase 8 addition:** add `let capturedVPNState = currentVPNState` immediately after line 229. This snapshot is read in the catch branch for the silent-failure reclassification (D-06).

#### Pattern 3: Silent-failure reclassification (extending the `runProbe` catch branch)

**Source:** `ConnectivityMonitor.swift:261-291` — the catch branch.

```swift
} catch {
    let latencyMs = Date().timeIntervalSince(start) * 1000

    // MON-03: Silent modem failure -- path says satisfied + cellular but probe fails.
    if capturedStatus == .satisfied && capturedInterface == .cellular {
        logEvent(
            type: .silentFailure,
            status: capturedStatus,
            interface: capturedInterface,
            isExpensive: false,
            isConstrained: false,
            probeLatencyMs: latencyMs,
            probeFailureReason: error.localizedDescription
        )
        if dropStartDate == nil {
            dropStartDate = Date()
        }
    } else {
        logEvent(
            type: .probeFailure,
            ...
        )
    }
}
```
> **Phase 8 transformation (D-06 + D-07):** extend the cellularity check to treat `.other` as cellular when a VPN is up AND the path uses cellular. Per RESEARCH.md lines 250-272:
> ```swift
> let effectivelyCellular = capturedInterface == .cellular ||
>     ((capturedVPNState == .connected
>       || capturedVPNState == .reasserting
>       || capturedVPNState == .connecting)
>      && pathMonitor.currentPath.usesInterfaceType(.cellular))
>
> if capturedStatus == .satisfied && effectivelyCellular {
>     logEvent(type: .silentFailure, ..., vpnState: capturedVPNState)
>     if dropStartDate == nil { dropStartDate = Date() }
> } else {
>     logEvent(type: .probeFailure, ..., vpnState: capturedVPNState)
> }
> ```
> **Note:** `pathMonitor.currentPath` requires `Network.NWPath` qualification at every reference site if `NWPath` appears (the file already imports `NetworkExtension` per line 5). RESEARCH.md flags this in `<established_patterns>`.

#### Pattern 4: Synchronous capture function with side-effect state update

**Source:** `ConnectivityMonitor.swift:338-341` — `captureRadioTechnology` (closest sync analog; `captureWifiSSID` is async and not the right precedent).

```swift
private func captureRadioTechnology() -> String? {
    let freshInfo = CTTelephonyNetworkInfo()
    return freshInfo.serviceCurrentRadioAccessTechnology?.values.first
}
```
> **Phase 8 addition:** new `captureVPNState() -> VPNState` that:
> 1. Calls `CFNetworkCopySystemProxySettings()` and scans `__SCOPED__` keys for `utun`/`ipsec`/`tap`/`tun`/`ppp` prefixes (RESEARCH.md lines 156-174).
> 2. Compares result against `previousVPNDetectorState: Bool` (new private property, parallel to `previousPathStatus` at line 48).
> 3. Returns inferred `VPNState` per the table in RESEARCH.md lines 182-189.
> 4. Updates `previousVPNDetectorState` as a side effect.
> 5. Honors the `vpnReassertingUntil: Date?` flag for `.reasserting` inference (RESEARCH.md lines 209-215).
> Function is `@MainActor`-isolated to match `handlePathUpdate` / `processPathChange` / `runProbe`.

#### Pattern 5: Live `@Observable` state property for dashboard binding

**Source:** `ConnectivityMonitor.swift:32-43` — the published-state block.

```swift
@Observable
final class ConnectivityMonitor {

    // MARK: - Published State (for UI binding)

    /// Whether the monitor is actively observing path changes.
    private(set) var isMonitoring: Bool = false

    /// Current network path status as last reported by NWPathMonitor.
    private(set) var currentPathStatus: PathStatus = .unsatisfied

    /// Current primary network interface type.
    private(set) var currentInterfaceType: InterfaceType = .unknown

    /// Current radio access technology string (e.g., "CTRadioAccessTechnologyNR").
    /// Updated live via CTTelephonyNetworkInfo notification.
    private(set) var currentRadioTechnology: String?
```
> **Phase 8 addition:** add `private(set) var currentVPNState: VPNState = .disconnected` here. Updated live in `handlePathUpdate` (mirror line 372 `currentInterfaceType = newInterface`). RESEARCH.md line 73 confirms this is recommended (parallel to `currentRadioTechnology`).

#### Pattern 6: Computed UI-display helper on the monitor (NEW — but see precedent)

**Precedent (closest analog):** there is no existing computed-display property on `ConnectivityMonitor` today. The closest precedent for "view-layer computed wrapper around model state" is the `radioTechDisplay` computed in `EventDetailView.swift:74-77`:

```swift
private var radioTechDisplay: String {
    guard let tech = event.radioTechnology else { return "Unknown" }
    return tech.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
}
```
> **Phase 8 addition:** `effectiveInterfaceLabel: String` lives on `ConnectivityMonitor` (not on the view) because it reads two `@Observable` properties (`currentVPNState` AND `currentInterfaceType`) and the dashboard needs SwiftUI to re-render when either changes. Implementation per UI-SPEC §DashboardView lines 198-203:
> ```swift
> /// Dashboard-only override: returns "VPN" when a VPN tunnel is connected or
> /// reasserting, otherwise the raw interface type's display name. Per UI-SPEC
> /// this override is NOT applied to detail view, list rows, or export — only
> /// the dashboard interface card consumes it.
> var effectiveInterfaceLabel: String {
>     if currentVPNState == .connected || currentVPNState == .reasserting {
>         return "VPN"
>     }
>     return currentInterfaceType.displayName
> }
> ```

#### Pattern 7: Import block (no new imports beyond what Phase 8 needs)

**Source:** `ConnectivityMonitor.swift:1-6`.

```swift
import Network
import Observation
import Foundation
import CoreTelephony
import NetworkExtension
import UserNotifications
```
> **Phase 8 addition:** `import SystemConfiguration` (for `CFNetworkCopySystemProxySettings`). RESEARCH.md line 101 confirms this framework is auto-linked and entitlement-free. NetworkExtension is already imported (Phase 7) but **not used for VPN detection in Phase 8** (only as the source of the `NEVPNStatus` enum vocabulary — see anti-pattern below).

---

### `CellGuard/Views/EventDetailView.swift` (component, request-response)

**Analog:** self — the Wi-Fi section is the precise template.

#### Pattern 1: Conditional Section block

**Source:** `EventDetailView.swift:30-34` — the Wi-Fi section.

```swift
if event.wifiSSID != nil {
    Section("Wi-Fi") {
        LabeledContent("SSID", value: event.wifiSSID?.isEmpty == true ? "\u{2014}" : event.wifiSSID!)
    }
}
```
> **Phase 8 substitution** per UI-SPEC structure block (lines 161-168), placed **between `Section("Wi-Fi")` (line 30-34) and the probe section (line 36)**:
> ```swift
> if let state = event.vpnState,
>    state != .disconnected,
>    state != .invalid {
>     Section("VPN") {
>         LabeledContent("State", value: state.displayName)
>     }
> }
> ```
> **Differences from Wi-Fi pattern:**
> - Visibility threshold is stricter: not just nil-check, but also `∉ {disconnected, invalid}` (UI-SPEC §Nil/Empty State Contract, locked by D-05).
> - No empty-string fallback — `displayName` is always non-empty for the four visible states.
> - No `\u{2014}` em-dash placeholder — when the section is hidden, it stays hidden (UI-SPEC line 179: "Never show '—', 'N/A', or 'Unknown' in this section").

#### Pattern 2: Section ordering

**Source:** `EventDetailView.swift:13-66` — the full body.

Existing order: Event → Network → Cellular → **Wi-Fi (cond)** → Probe (cond) → Location (cond) → Duration (cond).

> **Phase 8 ordering** per UI-SPEC line 154: Event → Network → Cellular → Wi-Fi → **VPN (cond)** → Probe → Location → Duration. The new VPN section sits **immediately after Wi-Fi**, before Probe. Rationale (UI-SPEC line 154-155): both are network-context layers above the cellular link; both are conditional; visual adjacency reinforces the semantic adjacency.

#### Pattern 3: `displayName` extension co-located with view

**Source:** `EventDetailView.swift:99-122` — the existing `PathStatus.displayName` and `InterfaceType.displayName` extensions.

```swift
extension InterfaceType {
    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .cellular: "Cellular"
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .loopback: "Loopback"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}
```
> **Phase 8 addition:** add `extension VPNState { var displayName: String { ... } }` immediately after `InterfaceType.displayName` (line 122), with the UI-SPEC-mandated string mapping (UI-SPEC table line 112-119):
> ```swift
> extension VPNState {
>     /// Human-readable name for UI display. The 6-state model projects to the
>     /// spec's 3-state vocabulary via `Reconnecting` (= reasserting).
>     var displayName: String {
>         switch self {
>         case .invalid: "Invalid"
>         case .disconnected: "Disconnected"
>         case .connecting: "Connecting"
>         case .connected: "Connected"
>         case .reasserting: "Reconnecting"     // ← NOT "Reasserting"
>         case .disconnecting: "Disconnecting"
>         }
>     }
> }
> ```
> The `Reconnecting` mapping is the single string that diverges from a literal title-case of the enum name (UI-SPEC line 121-126: "reasserting" is internal Apple-API jargon; "Reconnecting" is the human-language equivalent).

---

### `CellGuard/Views/DashboardView.swift` (component, request-response + binding)

**Analog:** self — both edits are single-line substitutions.

#### Pattern 1: Live `@Observable` Text binding (interface label flip)

**Source:** `DashboardView.swift:166-187` — the connectivity state card.

```swift
private var connectivityStateCard: some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Status")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(monitor.currentPathStatus.displayName)
                .font(.headline)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
            Text("Interface")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(monitor.currentInterfaceType.displayName)   // ← line 180: substitute here
                .font(.headline)
        }
    }
    .padding()
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
```
> **Phase 8 substitution (UI-SPEC §DashboardView lines 189-225):**
> ```swift
> Text(monitor.effectiveInterfaceLabel)
>     .font(.headline)
> ```
> No styling change. `.headline`, `.primary` foreground stay identical to existing "Cellular" / "Wi-Fi" / "Other" rendering. Reasserting is **not** visually distinguished from connected on the dashboard (UI-SPEC line 212-220: "no italic, no animated dot, no pulsing, no spinner").

#### Pattern 2: Privacy toggle copy update

**Source:** `DashboardView.swift:97`.

```swift
// Privacy toggle for export (EXPT-01, EXPT-03)
Toggle("Omit location and Wi-Fi data", isOn: $omitLocation)
    .font(.subheadline)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal)
    .padding(.bottom, 4)
```
> **Phase 8 substitution (UI-SPEC §Privacy Toggle lines 300-302):**
> ```swift
> Toggle("Omit location, Wi-Fi, and VPN data", isOn: $omitLocation)
> ```
> No logic change. `omitLocation` AppStorage key (line 15: `@AppStorage("omitLocationData")`) continues to drive the existing redaction. The label change is the entire UX delta — gating is unchanged because `vpnState` rides on the same `omitLocation` userInfo flag in `ConnectivityEvent.encode(to:)` (D-08).

---

## Shared Patterns (cross-cutting)

### Privacy Gating

**Source:** `ConnectivityEvent.swift:5-9` (the `CodingUserInfoKey.omitLocation` declaration) + `ConnectivityEvent.swift:267-273` (the redaction site).

```swift
// CodingUserInfoKey declaration (lines 5-9)
extension CodingUserInfoKey {
    /// When set to `true` on a JSONEncoder's userInfo, the encoder omits
    /// latitude, longitude, and locationAccuracy from the output.
    static let omitLocation = CodingUserInfoKey(rawValue: "omitLocation")!
}

// Redaction block (lines 267-273)
let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
if !omitLocation {
    try container.encodeIfPresent(latitude, forKey: .latitude)
    try container.encodeIfPresent(longitude, forKey: .longitude)
    try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)
}
```

**Apply to:** the `vpnState` field in `ConnectivityEvent.encode(to:)`.

**Pipeline (no changes needed at upstream sites):**
1. User flips `Toggle("Omit location, Wi-Fi, and VPN data", ...)` in `DashboardView.swift:97`.
2. `@AppStorage("omitLocationData")` (line 15) persists `true`/`false`.
3. `ShareLink` constructs `EventLogExport(events:..., omitLocation: omitLocation, ...)` at `DashboardView.swift:108`.
4. `EventLogExport.transferRepresentation` sets `encoder.userInfo[.omitLocation] = true` at `EventLogExport.swift:56-58`.
5. `ConnectivityEvent.encode(to:)` reads the flag and gates the four (soon five) fields at lines 267-273.

> **The plumbing is generic.** Phase 8 only modifies step 5 (add `vpnState` to the gate, with the additional `state ∉ {.disconnected, .invalid}` filter from UI-SPEC) and step 1 (label copy). All other steps are untouched.

### Race-Safe Pre-Await State Capture

**Source:** `ConnectivityMonitor.swift:227-229` — the comment "Pitfall 5".

```swift
// Pitfall 5: Capture state before awaiting probe to avoid race condition
let capturedStatus = currentPathStatus
let capturedInterface = currentInterfaceType
```
**Apply to:** any new `@MainActor`-mutated state that the probe's catch branch will read. For Phase 8, that means `currentVPNState`.

### Synchronous-Outside-Task / Async-Inside-Task Capture Split (D-09)

**Source:** `ConnectivityMonitor.swift:509-535`.

Sync values (`radioTech`, `carrier`, `location`) captured outside the `Task`. Async value (`ssid`) captured inside the Task before SwiftData persist.

**Apply to:** `vpnState`. RESEARCH.md confirms `CFNetworkCopySystemProxySettings()` is synchronous — capture outside the Task block.

### Network.NWPath Disambiguation

**Source:** `ConnectivityMonitor.swift:361, 465, 479` — three sites that explicitly qualify `Network.NWPath` because both `Network` and `NetworkExtension` are imported.

```swift
private func handlePathUpdate(_ path: Network.NWPath) { ... }
private func mapPathStatus(_ status: Network.NWPath.Status) -> PathStatus { ... }
private func detectPrimaryInterface(_ path: Network.NWPath) -> InterfaceType { ... }
```
**Apply to:** any new code path that references `NWPath` directly. `pathMonitor.currentPath.usesInterfaceType(.cellular)` (used in the silent-failure D-07 logic) does not need explicit qualification because `currentPath`'s type is inferred from the call chain, but if a new function signature accepts `NWPath`, qualify it.

### Anti-Patterns to Avoid (carry forward from RESEARCH.md)

- **Do NOT call `NEVPNManager.shared().connection.status` for VPN detection** (RESEARCH.md lines 131-139 + 477). It is calling-app-scoped — CellGuard owns no VPN config. Will always return `.invalid`/`.disconnected` for third-party tunnels (Mullvad, WireGuard, ProtonVPN, Settings VPN profiles).
- **Do NOT scan `getifaddrs()` for `utun*` interface names directly** (RESEARCH.md line 478). Apple system services use `utun0/1/2` even when no user VPN is up — false positives. The `__SCOPED__` dictionary discriminator is the workaround.
- **Do NOT use `path.usesInterfaceType(.other)` as the sole VPN signal** (RESEARCH.md line 479). `.other` fires for non-VPN scenarios too. Use it only as corroborating evidence inside the D-07 effectivelyCellular check.
- **Do NOT add a new `.vpn` case to `InterfaceType`** (D-04). Use the computed `effectiveInterfaceLabel` override instead — keeps `interfaceType` a faithful record of what `NWPath` reported and avoids a SwiftData enum migration.
- **Do NOT extend the dashboard label override to other surfaces** (UI-SPEC §DashboardView lines 229-237). Detail view shows raw `interfaceType.displayName` (ground truth); export carries raw `interfaceType` AND `vpnState` as separate fields; list rows don't show interface today and Phase 8 doesn't add it.

---

## No Analog Found

None. Every Phase 8 change site has a Phase 7 analog (or a Phase 6 race-safety analog) within the same file. The only genuinely new code is:

1. The `CFNetworkCopySystemProxySettings()` `__SCOPED__`-scanning detection function — RESEARCH.md provides a 14-line reference implementation at lines 156-174 with 4-source verification. No codebase analog (no other system-framework C-API calls in CellGuard today), but the pattern is fully specified.
2. The `vpnReassertingUntil: Date?` time-window flag for `.reasserting` inference — no exact analog, but conceptually parallel to `dropStartDate: Date?` at `ConnectivityMonitor.swift:54` (also a "transient state tracker" Date optional that is set on one transition and read until cleared/timed out).

Both are documented in RESEARCH.md §Detection Mechanism and §VPN-04 Decision Tree with full code shapes; the planner can copy them directly.

---

## Metadata

**Analog search scope:**
- `CellGuard/Models/ConnectivityEvent.swift` (full read)
- `CellGuard/Models/EventLogExport.swift` (full read)
- `CellGuard/Services/ConnectivityMonitor.swift` (full read)
- `CellGuard/Views/EventDetailView.swift` (full read)
- `CellGuard/Views/DashboardView.swift` (full read)
- Grep for `wifiSSID` / `omitLocation` across `CellGuard/**/*.swift` (5 files matched, all read above)

**Files scanned:** 5
**Pattern extraction date:** 2026-04-25
**Phase 7 PATTERNS reference:** `.planning/phases/07-wifi-context/07-PATTERNS.md` (per CONTEXT.md `<canonical_refs>` line 66 — read on demand by the planner if it needs additional Phase-7-specific framing).
