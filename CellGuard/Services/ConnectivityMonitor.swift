import Network
import Observation
import Foundation

/// Core detection engine that translates NWPathMonitor transitions into classified
/// ConnectivityEvent records and persists them through EventStore.
///
/// Handles four classification cases:
/// 1. Overt drop: path goes from satisfied to unsatisfied/requiresConnection
/// 2. Connectivity restored: path recovers to satisfied (with drop duration calculation)
/// 3. Wi-Fi fallback: device silently falls back from cellular to Wi-Fi (MON-06)
/// 4. Other meaningful transition: any other status or interface change
///
/// Design notes:
/// - NWPathMonitor cannot be restarted after cancel(). If monitoring needs to resume
///   after stopMonitoring(), a new NWPathMonitor instance must be created. Currently
///   this class creates the monitor once; restart support would require recreating it.
/// - The initial NWPathMonitor callback is suppressed to avoid logging a spurious event
///   on startup (the first callback reports current state, not a transition).
/// - Rapid path flapping within 500ms is debounced to a single event.
@Observable
final class ConnectivityMonitor {

    // MARK: - Published State (for future UI binding)

    /// Whether the monitor is actively observing path changes.
    private(set) var isMonitoring: Bool = false

    /// Current network path status as last reported by NWPathMonitor.
    private(set) var currentPathStatus: PathStatus = .unsatisfied

    /// Current primary network interface type.
    private(set) var currentInterfaceType: InterfaceType = .unknown

    /// Current radio access technology string (e.g., "CTRadioAccessTechnologyNR").
    /// Populated by Plan 02 (CTTelephonyNetworkInfo integration).
    private(set) var currentRadioTechnology: String?

    // MARK: - Internal State for Classification

    /// Previous path status, used to detect transitions.
    private var previousPathStatus: PathStatus = .unsatisfied

    /// Previous interface type, used to detect Wi-Fi fallback (MON-06).
    private var previousInterfaceType: InterfaceType = .unknown

    /// Timestamp when a connectivity drop began. Used to calculate drop duration (DAT-02).
    private var dropStartDate: Date?

    /// Guards against logging the initial NWPathMonitor callback as an event.
    /// The first callback reports current state, not a transition.
    private var isInitialUpdate: Bool = true

    /// Active debounce task. Cancelled and replaced on each rapid path update.
    private var debounceTask: Task<Void, Never>?

    /// Last known location, set externally by Phase 3 location provider.
    /// Attached to every logged event for geographic pattern analysis.
    private var lastLocation: (latitude: Double, longitude: Double, accuracy: Double)?

    // MARK: - Dependencies

    /// The NWPathMonitor instance that delivers path change callbacks.
    private let pathMonitor = NWPathMonitor()

    /// Dedicated queue for NWPathMonitor callbacks, off the main thread.
    private let monitorQueue = DispatchQueue(label: "com.cellguard.pathmonitor")

    /// Persistence layer for writing classified events.
    private let eventStore: EventStore

    // MARK: - Initializer

    /// Creates a ConnectivityMonitor with the given EventStore for persistence.
    /// - Parameter eventStore: The actor-isolated store for writing ConnectivityEvent records.
    init(eventStore: EventStore) {
        self.eventStore = eventStore
    }

    // MARK: - Public API

    /// Starts monitoring network path changes via NWPathMonitor.
    ///
    /// Sets up the path update handler and begins delivering callbacks on `monitorQueue`.
    /// The first callback is suppressed (initial state capture, not a transition).
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isInitialUpdate = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }

        pathMonitor.start(queue: monitorQueue)
    }

    /// Stops monitoring and cancels any pending debounce task.
    ///
    /// Note: NWPathMonitor cannot be restarted after cancel(). To resume monitoring,
    /// a new ConnectivityMonitor instance must be created.
    func stopMonitoring() {
        pathMonitor.cancel()
        // Probe timer placeholder -- Plan 02 adds the actual timer
        isMonitoring = false
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Updates the last known location, attached to all subsequent events.
    ///
    /// Called by Phase 3 location provider (CLLocationManager significant location changes).
    /// - Parameters:
    ///   - latitude: Latitude in degrees.
    ///   - longitude: Longitude in degrees.
    ///   - accuracy: Horizontal accuracy in meters.
    func updateLocation(latitude: Double, longitude: Double, accuracy: Double) {
        lastLocation = (latitude: latitude, longitude: longitude, accuracy: accuracy)
    }

    // MARK: - Path Update Handling

    /// Processes a raw NWPath update: maps status/interface, guards initial callback,
    /// and debounces rapid changes before classification.
    @MainActor
    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = mapPathStatus(path.status)
        let newInterface = detectPrimaryInterface(path)
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained

        // Pitfall 1: The initial NWPathMonitor callback reports current state,
        // not a transition. Capture it silently without logging an event.
        if isInitialUpdate {
            previousPathStatus = newStatus
            previousInterfaceType = newInterface
            currentPathStatus = newStatus
            currentInterfaceType = newInterface
            isInitialUpdate = false
            return
        }

        // Pitfall 6: Debounce rapid path flapping. Cancel any pending classification
        // and wait 500ms before processing. Only the last update in a rapid sequence
        // produces an event.
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.processPathChange(
                newStatus: newStatus,
                newInterface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        }
    }

    // MARK: - Event Classification

    /// Classifies a debounced path change into the correct EventType and logs it.
    ///
    /// Classification priority:
    /// 1. Overt drop (satisfied -> unsatisfied/requiresConnection)
    /// 2. Connectivity restored (unsatisfied/requiresConnection -> satisfied) with drop duration
    /// 3. Wi-Fi fallback (cellular -> wifi while satisfied) (MON-06)
    /// 4. Other meaningful transition (any remaining status or interface change)
    @MainActor
    private func processPathChange(
        newStatus: PathStatus,
        newInterface: InterfaceType,
        isExpensive: Bool,
        isConstrained: Bool
    ) {
        // Case 1 -- Overt drop: path was satisfied, now unsatisfied or requiresConnection
        if previousPathStatus == .satisfied && (newStatus == .unsatisfied || newStatus == .requiresConnection) {
            dropStartDate = Date()
            logEvent(
                type: .pathChange,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        }
        // Case 2 -- Connectivity restored: path was down, now satisfied (DAT-02)
        else if (previousPathStatus == .unsatisfied || previousPathStatus == .requiresConnection) && newStatus == .satisfied {
            let dropDuration = dropStartDate.map { Date().timeIntervalSince($0) }
            dropStartDate = nil
            logEvent(
                type: .connectivityRestored,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                dropDuration: dropDuration
            )
        }
        // Case 3 -- Wi-Fi fallback (MON-06): device silently fell back from cellular to Wi-Fi
        else if previousInterfaceType == .cellular && newInterface == .wifi && newStatus == .satisfied {
            logEvent(
                type: .pathChange,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        }
        // Case 4 -- Other meaningful transition: any remaining status or interface change
        else if newStatus != previousPathStatus || newInterface != previousInterfaceType {
            logEvent(
                type: .pathChange,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        }

        // Update tracked state after classification
        previousPathStatus = newStatus
        previousInterfaceType = newInterface
        currentPathStatus = newStatus
        currentInterfaceType = newInterface
    }

    // MARK: - Helpers

    /// Maps NWPath.Status to the app's PathStatus enum.
    private func mapPathStatus(_ status: NWPath.Status) -> PathStatus {
        switch status {
        case .satisfied: return .satisfied
        case .unsatisfied: return .unsatisfied
        case .requiresConnection: return .requiresConnection
        @unknown default: return .unsatisfied
        }
    }

    /// Detects the primary network interface from an NWPath.
    ///
    /// Uses `availableInterfaces` (ordered by system preference) rather than
    /// `usesInterfaceType()` to avoid the pitfall where multiple interface types
    /// return true simultaneously (e.g., both cellular and wifi).
    private func detectPrimaryInterface(_ path: NWPath) -> InterfaceType {
        guard let primaryInterface = path.availableInterfaces.first else {
            return .unknown
        }

        switch primaryInterface.type {
        case .cellular: return .cellular
        case .wifi: return .wifi
        case .wiredEthernet: return .wiredEthernet
        case .loopback: return .loopback
        case .other: return .other
        @unknown default: return .other
        }
    }

    /// Creates a ConnectivityEvent with all available metadata and persists it via EventStore.
    ///
    /// Radio technology and carrier name are nil for now (Plan 02 adds CTTelephonyNetworkInfo).
    /// Location is attached from `lastLocation` if available (Phase 3 provides updates).
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
            radioTechnology: nil,  // Plan 02: CTTelephonyNetworkInfo integration
            carrierName: nil,      // Plan 02: CTCarrier (deprecated, best-effort)
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
}
