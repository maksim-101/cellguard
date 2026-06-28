import SwiftData
import Foundation
import CoreLocation

extension CodingUserInfoKey {
    /// When set to `true` on a JSONEncoder's userInfo, the encoder omits
    /// latitude, longitude, and locationAccuracy from the output.
    static let omitLocation = CodingUserInfoKey(rawValue: "omitLocation")!
}

// MARK: - Enums with explicit Int raw values (never rely on auto-increment -- migration safety)

/// Classification of connectivity events detected by CellGuard.
enum EventType: Int, Codable, CaseIterable {
    case pathChange = 0
    case silentFailure = 1
    case probeSuccess = 2
    case probeFailure = 3
    case connectivityRestored = 4
    case monitoringGap = 5
    /// Logged when the VPN tunnel crosses the absent↔present boundary (disconnected/invalid ↔
    /// connecting/connected/reasserting/disconnecting). Not a drop — no notification is sent.
    /// Explicit rawValue 6 prevents accidental re-assignment if cases are reordered (migration safety).
    case vpnStateChange = 6
    /// Logged when a cellular download-throughput measurement falls below slowThroughputThresholdKbps.
    /// Not a drop — no notification is sent. Explicit rawValue 7 for migration safety.
    case slowThroughput = 7
    /// Logged when a throughput measurement falls below severeThroughputThresholdKbps — bulk data
    /// is effectively unusable (reachability still succeeds, but a 100KB transfer crawls). Counts as
    /// a drop, distinct from .slowThroughput (degraded but functional). Explicit rawValue 8 (migration safety).
    case severeThroughput = 8
}

/// Network path status as reported by NWPathMonitor.
enum PathStatus: Int, Codable {
    case satisfied = 0
    case unsatisfied = 1
    case requiresConnection = 2
}

/// Network interface type for the active path.
enum InterfaceType: Int, Codable {
    case cellular = 0
    case wifi = 1
    case wiredEthernet = 2
    case loopback = 3
    case other = 4
    case unknown = 5
}

/// VPN tunnel state, mirroring NEVPNStatus vocabulary. Stored as Int rawValue (D-03).
/// Sourced via CFNetworkCopySystemProxySettings detection (Plan 03), not NEVPNManager --
/// see 08-RESEARCH.md "Detection Mechanism" for why NEVPNManager is unsuitable.
enum VPNState: Int, Codable {
    case invalid = 0
    case disconnected = 1
    case connecting = 2
    case connected = 3
    case reasserting = 4
    case disconnecting = 5
}

// MARK: - ConnectivityEvent Model

/// A single connectivity event captured by CellGuard.
///
/// All DAT-01 metadata fields are stored as properties. Enum fields use the rawValue
/// storage pattern because SwiftData does not support enum types in `#Predicate` queries.
/// CLLocationCoordinate2D is decomposed into separate latitude/longitude Doubles because
/// SwiftData cannot store C structs directly.
@Model
final class ConnectivityEvent {

    // MARK: Timestamps

    /// Event timestamp in local timezone
    var timestamp: Date

    /// Same instant as `timestamp`, stored separately for export clarity
    var timestampUTC: Date

    // MARK: Event classification (rawValue storage for predicate support)

    /// Raw integer storage for EventType enum. Use `eventType` computed property for typed access.
    var eventTypeRaw: Int

    /// Raw integer storage for PathStatus enum. Use `pathStatus` computed property for typed access.
    var pathStatusRaw: Int

    /// Raw integer storage for InterfaceType enum. Use `interfaceType` computed property for typed access.
    var interfaceTypeRaw: Int

    // MARK: Network path flags

    /// Whether the network path is considered expensive (e.g., cellular data)
    var isExpensive: Bool

    /// Whether the network path is constrained (e.g., Low Data Mode)
    var isConstrained: Bool

    /// Whether Low Power Mode was enabled at the time of the event.
    /// Source: `ProcessInfo.processInfo.isLowPowerModeEnabled`.
    /// Declaration default `= false` is REQUIRED for SwiftData lightweight migration:
    /// existing rows have no value for this new mandatory column, and SwiftData reads the
    /// property-declaration default (NOT the init default) to backfill them. Without it,
    /// adding this non-optional attribute crashes on launch with a 134110 migration error.
    var lowPowerMode: Bool = false

    /// Whether the underlying network path used a cellular interface at the time of the event.
    /// Source: `NWPath.usesInterfaceType(.cellular)`. This is the RELIABLE cellular discriminator
    /// for health scoring: unlike `isExpensive` (which reads false through a VPN tunnel), this stays
    /// true for cellular-backed traffic even when a VPN like Tailscale is active. Declaration default
    /// `= false` is REQUIRED for SwiftData lightweight migration (see lowPowerMode note above).
    var pathUsesCellular: Bool = false

    // MARK: Cellular metadata

    /// Radio access technology string, e.g. "CTRadioAccessTechnologyNR" for 5G. Nil if unknown.
    var radioTechnology: String?

    /// Carrier name from CTTelephonyNetworkInfo. May be nil due to CTCarrier deprecation on iOS 16.4+.
    var carrierName: String?

    // MARK: Cellular restriction metadata

    /// Cellular data access restriction state at the time of the event.
    /// Possible values: "restricted", "notRestricted", "unknown". Nil for legacy events
    /// captured before Task 2. Sourced from CTCellularData.restrictedState via the
    /// cellularDataRestrictionDidUpdateNotifier; "unknown" until the first notifier callback.
    var cellularDataRestricted: String?

    // MARK: Wi-Fi metadata

    /// Wi-Fi SSID at the time of the event. Nil if not connected to Wi-Fi or SSID could not be captured.
    var wifiSSID: String?

    // MARK: VPN metadata

    /// Raw integer storage for VPNState enum. nil for legacy events captured before Phase 8.
    /// Use `vpnState` computed property for typed access.
    var vpnStateRaw: Int?

    /// Typed accessor for VPN tunnel state. Optional because legacy events have no VPN metadata
    /// and because `nil` is a meaningful "we did not capture VPN state for this event" signal.
    var vpnState: VPNState? {
        get { vpnStateRaw.flatMap(VPNState.init(rawValue:)) }
        set { vpnStateRaw = newValue?.rawValue }
    }

    /// Matched tunnel interface key at the time of the event (e.g. "utun3"). Nil when no
    /// VPN tunnel was detected or for legacy events before Task 3. Export-gated alongside
    /// vpnState (omitted when encoder userInfo has omitLocation = true).
    var vpnInterface: String?

    // MARK: Active probe results

    /// Round-trip latency of the connectivity probe in milliseconds. Nil if probe was not performed.
    var probeLatencyMs: Double?

    /// Measured cellular download rate in Kbps for throughput-sampling events.
    /// Nil when no throughput was measured for this event.
    var throughputKbps: Double?

    /// Reason the connectivity probe failed. Nil if probe succeeded or was not performed.
    var probeFailureReason: String?

    // MARK: Location (decomposed from CLLocationCoordinate2D)

    /// Latitude component of the event location. Nil if location was unavailable.
    var latitude: Double?

    /// Longitude component of the event location. Nil if location was unavailable.
    var longitude: Double?

    /// Horizontal accuracy of the location fix in meters. Nil if location was unavailable.
    var locationAccuracy: Double?

    // MARK: Drop duration

    /// Duration of the connectivity drop in seconds. Calculated in Phase 2, nil until then.
    var dropDurationSeconds: Double?

    // MARK: Computed enum accessors

    /// Typed accessor for the event type. Maps to/from `eventTypeRaw` for SwiftData predicate compatibility.
    var eventType: EventType {
        get { EventType(rawValue: eventTypeRaw) ?? .pathChange }
        set { eventTypeRaw = newValue.rawValue }
    }

    /// Typed accessor for the path status. Maps to/from `pathStatusRaw` for SwiftData predicate compatibility.
    var pathStatus: PathStatus {
        get { PathStatus(rawValue: pathStatusRaw) ?? .unsatisfied }
        set { pathStatusRaw = newValue.rawValue }
    }

    /// Typed accessor for the interface type. Maps to/from `interfaceTypeRaw` for SwiftData predicate compatibility.
    var interfaceType: InterfaceType {
        get { InterfaceType(rawValue: interfaceTypeRaw) ?? .unknown }
        set { interfaceTypeRaw = newValue.rawValue }
    }

    // MARK: Location reconstruction

    /// Reconstructs a CLLocationCoordinate2D from stored latitude/longitude. Returns nil if either is missing.
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Generates a stable string key for a ~1.1km grid cell containing this event.
    /// Used for location-based analytics (ANALYTICS-01, ANALYTICS-02).
    var locationCluster: String? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return "\(String(format: "%.2f", lat)), \(String(format: "%.2f", lon))"
    }

    // MARK: Initializer

    init(
        timestamp: Date = .now,
        eventType: EventType,
        pathStatus: PathStatus,
        interfaceType: InterfaceType,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        lowPowerMode: Bool = false,
        pathUsesCellular: Bool = false,
        radioTechnology: String? = nil,
        carrierName: String? = nil,
        cellularDataRestricted: String? = nil,
        wifiSSID: String? = nil,
        vpnState: VPNState? = nil,
        vpnInterface: String? = nil,
        probeLatencyMs: Double? = nil,
        throughputKbps: Double? = nil,
        probeFailureReason: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracy: Double? = nil,
        dropDurationSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.timestampUTC = timestamp // Same Date object; formatting handles timezone
        self.eventTypeRaw = eventType.rawValue
        self.pathStatusRaw = pathStatus.rawValue
        self.interfaceTypeRaw = interfaceType.rawValue
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.lowPowerMode = lowPowerMode
        self.pathUsesCellular = pathUsesCellular
        self.radioTechnology = radioTechnology
        self.carrierName = carrierName
        self.cellularDataRestricted = cellularDataRestricted
        self.wifiSSID = wifiSSID
        self.vpnStateRaw = vpnState?.rawValue
        self.vpnInterface = vpnInterface
        self.probeLatencyMs = probeLatencyMs
        self.throughputKbps = throughputKbps
        self.probeFailureReason = probeFailureReason
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracy = locationAccuracy
        self.dropDurationSeconds = dropDurationSeconds
    }
}

// MARK: - Codable Conformance

extension ConnectivityEvent: Codable {

    enum CodingKeys: String, CodingKey {
        case timestamp
        case timestampUTC
        case eventType
        case pathStatus
        case interfaceType
        case isExpensive
        case isConstrained
        case lowPowerMode
        case pathUsesCellular
        case radioTechnology
        case carrierName
        case cellularDataRestricted
        case probeLatencyMs
        case throughputKbps
        case probeFailureReason
        case latitude
        case longitude
        case locationAccuracy
        case wifiSSID
        case vpnState
        case vpnInterface
        case dropDurationSeconds
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Decode enums: try String-based encoding first, fall back to Int for legacy files
        let eventType: EventType
        if let str = try? container.decode(String.self, forKey: .eventType),
           let decoded = EventType.fromEncodingString(str) {
            eventType = decoded
        } else {
            eventType = try container.decode(EventType.self, forKey: .eventType)
        }

        let pathStatus: PathStatus
        if let str = try? container.decode(String.self, forKey: .pathStatus),
           let decoded = PathStatus.fromEncodingString(str) {
            pathStatus = decoded
        } else {
            pathStatus = try container.decode(PathStatus.self, forKey: .pathStatus)
        }

        let interfaceType: InterfaceType
        if let str = try? container.decode(String.self, forKey: .interfaceType),
           let decoded = InterfaceType.fromEncodingString(str) {
            interfaceType = decoded
        } else {
            interfaceType = try container.decode(InterfaceType.self, forKey: .interfaceType)
        }

        // VPNState: try String-based encoding first, fall back to Int rawValue for legacy files.
        // `try?` returns nil on a missing key, which correctly maps to vpnState = nil.
        let vpnState: VPNState?
        if let str = try? container.decode(String.self, forKey: .vpnState) {
            vpnState = VPNState.fromEncodingString(str)
        } else if let raw = try? container.decode(Int.self, forKey: .vpnState) {
            vpnState = VPNState(rawValue: raw)
        } else {
            vpnState = nil
        }

        self.init(
            timestamp: timestamp,
            eventType: eventType,
            pathStatus: pathStatus,
            interfaceType: interfaceType,
            isExpensive: try container.decode(Bool.self, forKey: .isExpensive),
            isConstrained: try container.decode(Bool.self, forKey: .isConstrained),
            // decodeIfPresent ?? false: legacy export files lacking this key still decode cleanly
            // (differs from isConstrained's non-optional decode, which was written before migration-safety mattered)
            lowPowerMode: try container.decodeIfPresent(Bool.self, forKey: .lowPowerMode) ?? false,
            pathUsesCellular: try container.decodeIfPresent(Bool.self, forKey: .pathUsesCellular) ?? false,
            radioTechnology: try container.decodeIfPresent(String.self, forKey: .radioTechnology),
            carrierName: try container.decodeIfPresent(String.self, forKey: .carrierName),
            cellularDataRestricted: try container.decodeIfPresent(String.self, forKey: .cellularDataRestricted),
            wifiSSID: try container.decodeIfPresent(String.self, forKey: .wifiSSID),
            vpnState: vpnState,
            vpnInterface: try container.decodeIfPresent(String.self, forKey: .vpnInterface),
            probeLatencyMs: try container.decodeIfPresent(Double.self, forKey: .probeLatencyMs),
            throughputKbps: try container.decodeIfPresent(Double.self, forKey: .throughputKbps),
            probeFailureReason: try container.decodeIfPresent(String.self, forKey: .probeFailureReason),
            latitude: try container.decodeIfPresent(Double.self, forKey: .latitude),
            longitude: try container.decodeIfPresent(Double.self, forKey: .longitude),
            locationAccuracy: try container.decodeIfPresent(Double.self, forKey: .locationAccuracy),
            dropDurationSeconds: try container.decodeIfPresent(Double.self, forKey: .dropDurationSeconds)
        )
        self.timestampUTC = try container.decode(Date.self, forKey: .timestampUTC)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(timestampUTC, forKey: .timestampUTC)
        // Encode enums as human-readable strings (not raw Ints) for export readability
        try container.encode(eventType.encodingString, forKey: .eventType)
        try container.encode(pathStatus.encodingString, forKey: .pathStatus)
        try container.encode(interfaceType.encodingString, forKey: .interfaceType)
        try container.encode(isExpensive, forKey: .isExpensive)
        try container.encode(isConstrained, forKey: .isConstrained)
        try container.encode(lowPowerMode, forKey: .lowPowerMode)
        try container.encode(pathUsesCellular, forKey: .pathUsesCellular)
        try container.encodeIfPresent(radioTechnology, forKey: .radioTechnology)
        try container.encodeIfPresent(carrierName, forKey: .carrierName)
        // Omit "unknown" cellular restriction state from export — same noise-reduction principle
        // as the vpnState guard below; only meaningful values reach the export file.
        if let restriction = cellularDataRestricted, restriction != "unknown" {
            try container.encode(restriction, forKey: .cellularDataRestricted)
        }
        try container.encodeIfPresent(probeLatencyMs, forKey: .probeLatencyMs)
        try container.encodeIfPresent(throughputKbps, forKey: .throughputKbps)
        try container.encodeIfPresent(probeFailureReason, forKey: .probeFailureReason)
        let omitLocation = encoder.userInfo[.omitLocation] as? Bool ?? false
        if !omitLocation {
            try container.encodeIfPresent(latitude, forKey: .latitude)
            try container.encodeIfPresent(longitude, forKey: .longitude)
            try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
            try container.encodeIfPresent(wifiSSID, forKey: .wifiSSID)
            // Omit non-meaningful VPN states from export (UI-SPEC §Export -- JSON).
            if let state = vpnState, state != .disconnected, state != .invalid {
                try container.encode(state.encodingString, forKey: .vpnState)
            }
            // Export vpnInterface alongside vpnState (same omitLocation gate).
            try container.encodeIfPresent(vpnInterface, forKey: .vpnInterface)
        }
        try container.encodeIfPresent(dropDurationSeconds, forKey: .dropDurationSeconds)
    }
}

// MARK: - JSON Encoding Strings (stable, machine-friendly identifiers for export)

extension EventType {
    /// Stable camelCase identifier for JSON export. Distinct from `displayName` (which is for UI).
    var encodingString: String {
        switch self {
        case .pathChange: "pathChange"
        case .silentFailure: "silentFailure"
        case .probeSuccess: "probeSuccess"
        case .probeFailure: "probeFailure"
        case .connectivityRestored: "connectivityRestored"
        case .monitoringGap: "monitoringGap"
        case .vpnStateChange: "vpnStateChange"
        case .slowThroughput: "slowThroughput"
        case .severeThroughput: "severeThroughput"
        }
    }

    /// Decodes from a stable encoding string. Returns nil if the string is unrecognized.
    static func fromEncodingString(_ string: String) -> EventType? {
        switch string {
        case "pathChange": .pathChange
        case "silentFailure": .silentFailure
        case "probeSuccess": .probeSuccess
        case "probeFailure": .probeFailure
        case "connectivityRestored": .connectivityRestored
        case "monitoringGap": .monitoringGap
        case "vpnStateChange": .vpnStateChange
        case "slowThroughput": .slowThroughput
        case "severeThroughput": .severeThroughput
        default: nil
        }
    }
}

extension PathStatus {
    /// Stable camelCase identifier for JSON export.
    var encodingString: String {
        switch self {
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .requiresConnection: "requiresConnection"
        }
    }

    /// Decodes from a stable encoding string. Returns nil if the string is unrecognized.
    static func fromEncodingString(_ string: String) -> PathStatus? {
        switch string {
        case "satisfied": .satisfied
        case "unsatisfied": .unsatisfied
        case "requiresConnection": .requiresConnection
        default: nil
        }
    }
}

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

    /// Decodes from a stable encoding string. Returns nil if the string is unrecognized.
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

extension VPNState {
    /// Stable camelCase identifier for JSON export. Lowercased NEVPNStatus enum names.
    var encodingString: String {
        switch self {
        case .invalid: "invalid"
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .reasserting: "reasserting"
        case .disconnecting: "disconnecting"
        }
    }

    /// Decodes from a stable encoding string. Returns nil if the string is unrecognized.
    static func fromEncodingString(_ string: String) -> VPNState? {
        switch string {
        case "invalid": .invalid
        case "disconnected": .disconnected
        case "connecting": .connecting
        case "connected": .connected
        case "reasserting": .reasserting
        case "disconnecting": .disconnecting
        default: nil
        }
    }
}

// MARK: - Display Names

extension EventType {
    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .pathChange: "Path Change"
        case .silentFailure: "Silent Failure"
        case .probeSuccess: "Probe Success"
        case .probeFailure: "Probe Failure"
        case .connectivityRestored: "Connectivity Restored"
        case .monitoringGap: "Monitoring Gap"
        case .vpnStateChange: "VPN State Change"
        case .slowThroughput: "Slow Throughput"
        case .severeThroughput: "Severe Throughput"
        }
    }
}
