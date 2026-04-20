import Network
import Observation
import Foundation
import CoreTelephony
import UserNotifications

/// Core detection engine that translates NWPathMonitor transitions into classified
/// ConnectivityEvent records and persists them through EventStore.
///
/// Handles five classification cases:
/// 1. Overt drop: path goes from satisfied to unsatisfied/requiresConnection
/// 2. Connectivity restored: path recovers to satisfied (with drop duration calculation)
/// 3. Wi-Fi fallback: device silently falls back from cellular to Wi-Fi (MON-06)
/// 4. Silent modem failure: probe fails while path reports satisfied + cellular (MON-03)
/// 5. Other meaningful transition: any other status or interface change
///
/// Design notes:
/// - NWPathMonitor cannot be restarted after cancel(). If monitoring needs to resume
///   after stopMonitoring(), a new NWPathMonitor instance must be created. Currently
///   this class creates the monitor once; restart support would require recreating it.
/// - The initial NWPathMonitor callback is suppressed to avoid logging a spurious event
///   on startup (the first callback reports current state, not a transition).
/// - Rapid path flapping within 500ms is debounced to a single event.
/// - HEAD probe fires every 60s in foreground. Timer is paused in background since iOS
///   suspends timers anyway. Phase 3 adds wake-then-probe via significant location changes.
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

    // MARK: - Probe Properties (MON-02)

    /// Timer that fires the HEAD probe every 60 seconds in foreground.
    /// Paused in background (iOS suspends timers). Phase 3 adds wake-then-probe.
    private var probeTimer: Timer?

    /// URL for the active connectivity probe. Apple's captive portal detection endpoint
    /// is lightweight, always up, and raises no privacy concerns.
    private let probeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!

    /// Timeout for each HEAD probe request. 10 seconds is generous but catches slow failures.
    private let probeTimeout: TimeInterval = 10

    /// Interval between probe firings. 60 seconds balances detection speed with battery.
    private let probeInterval: TimeInterval = 60

    /// Reusable URLSession for probes. One session for all probes (not per-probe).
    /// `waitsForConnectivity = false` ensures immediate failure when network is down,
    /// which is essential for detecting silent modem failures.
    /// Note: Cannot use `lazy` with @Observable macro, so we use nonisolated(unsafe)
    /// static factory instead.
    private let probeSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - CoreTelephony (MON-04, MON-05)

    /// CTTelephonyNetworkInfo instance for notification registration.
    /// IMPORTANT: A single instance can return stale radio tech values. The captureRadioTechnology()
    /// method creates a fresh instance each time to ensure current values are read.
    /// This is a known behavior where the dictionary returned by serviceCurrentRadioAccessTechnology
    /// on a long-lived instance may not reflect settings changes (e.g., user switching LTE <-> 5G).
    private let networkInfo = CTTelephonyNetworkInfo()

    /// NotificationCenter observer token for radio tech changes, stored for cleanup on stop.
    private var radioTechObserver: (any NSObjectProtocol)?

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

    /// Starts monitoring network path changes via NWPathMonitor, sets up CoreTelephony
    /// radio tech observation, and begins the 60-second HEAD probe cycle.
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

        // CoreTelephony: register for radio tech changes and capture initial state.
        // Use a fresh CTTelephonyNetworkInfo for the initial read to avoid stale cached values.
        setupRadioTechObserver()
        currentRadioTechnology = CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology?.values.first

        // Start the 60-second HEAD probe cycle
        startProbeTimer()

        // Request notification authorization for drop alerts (MON-07)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Stops monitoring and cancels any pending debounce task and probe timer.
    ///
    /// Note: NWPathMonitor cannot be restarted after cancel(). To resume monitoring,
    /// a new ConnectivityMonitor instance must be created.
    func stopMonitoring() {
        pathMonitor.cancel()
        stopProbeTimer()
        removeRadioTechObserver()
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

    // MARK: - Probe Timer Management

    /// Starts (or restarts) the 60-second HEAD probe timer.
    /// Called on app launch and when returning to foreground.
    ///
    /// The first probe is delayed by 5 seconds to avoid false positive silent failure
    /// classifications at launch. NWPathMonitor's initial callback may not have fired yet,
    /// leaving currentPathStatus/currentInterfaceType stale, and the network may not be
    /// fully established after a background wake. Without this delay, the probe can fail
    /// while path status is stale-satisfied+cellular, producing a spurious silentFailure event.
    func startProbeTimer() {
        stopProbeTimer() // Safety: invalidate any existing timer
        probeTimer = Timer.scheduledTimer(withTimeInterval: probeInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.runProbe() }
        }
        // Delay first probe to let NWPathMonitor deliver initial state and network stabilize
        Task {
            try? await Task.sleep(for: .seconds(5))
            await runProbe()
        }
    }

    /// Stops the probe timer. Called when entering background since iOS suspends timers anyway.
    /// Phase 3 adds wake-then-probe via significant location changes for background probing.
    func stopProbeTimer() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    /// Public entry point for background wake-then-probe pattern.
    /// Called by LocationService on significant location change and by BGAppRefreshTask handler.
    @MainActor
    func runSingleProbe() async {
        await runProbe()
    }

    // MARK: - HEAD Probe (MON-02, MON-03)

    /// Performs a single HEAD request to Apple's captive portal to verify actual connectivity.
    ///
    /// Detects silent modem failures (MON-03): when the probe fails but NWPathMonitor still
    /// reports the path as satisfied on cellular, the modem is "attached but unreachable."
    ///
    /// Captures path state BEFORE awaiting the probe result to avoid the race condition
    /// where path status changes during the request (Pitfall 5 from research).
    @MainActor
    private func runProbe() async {
        // Pitfall 5: Capture state before awaiting probe to avoid race condition
        let capturedStatus = currentPathStatus
        let capturedInterface = currentInterfaceType

        var request = URLRequest(url: probeURL)
        request.httpMethod = "HEAD"

        let start = Date()

        do {
            let (_, response) = try await probeSession.data(for: request)
            let latencyMs = Date().timeIntervalSince(start) * 1000

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logEvent(
                    type: .probeSuccess,
                    status: capturedStatus,
                    interface: capturedInterface,
                    isExpensive: false,
                    isConstrained: false,
                    probeLatencyMs: latencyMs
                )
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logEvent(
                    type: .probeFailure,
                    status: capturedStatus,
                    interface: capturedInterface,
                    isExpensive: false,
                    isConstrained: false,
                    probeLatencyMs: latencyMs,
                    probeFailureReason: "HTTP \(statusCode)"
                )
            }
        } catch {
            let latencyMs = Date().timeIntervalSince(start) * 1000

            // MON-03: Silent modem failure -- path says satisfied + cellular but probe fails.
            // This is the "attached but unreachable" state the app is designed to catch.
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
                // Start tracking drop duration if not already in a drop
                if dropStartDate == nil {
                    dropStartDate = Date()
                }
            } else {
                logEvent(
                    type: .probeFailure,
                    status: capturedStatus,
                    interface: capturedInterface,
                    isExpensive: false,
                    isConstrained: false,
                    probeLatencyMs: latencyMs,
                    probeFailureReason: error.localizedDescription
                )
            }
        }
    }

    // MARK: - CoreTelephony Observers

    /// Registers for radio access technology change notifications via NotificationCenter.
    /// Updates `currentRadioTechnology` on the main actor when the radio tech changes
    /// (e.g., switching from LTE to 5G NR, or losing radio entirely).
    ///
    /// Uses a fresh CTTelephonyNetworkInfo instance in the callback because the long-lived
    /// `networkInfo` property can return stale values after iOS settings changes.
    private func setupRadioTechObserver() {
        // Remove any existing observer to prevent duplicates on restart
        if let existing = radioTechObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        radioTechObserver = NotificationCenter.default.addObserver(
            forName: .CTServiceRadioAccessTechnologyDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Create a fresh instance to avoid stale cached values
            let freshInfo = CTTelephonyNetworkInfo()
            let newTech = freshInfo.serviceCurrentRadioAccessTechnology?.values.first
            Task { @MainActor in
                self?.currentRadioTechnology = newTech
            }
        }
    }

    /// Removes the radio tech notification observer. Called during stopMonitoring()
    /// to prevent duplicate observers if monitoring is restarted.
    private func removeRadioTechObserver() {
        if let existing = radioTechObserver {
            NotificationCenter.default.removeObserver(existing)
            radioTechObserver = nil
        }
    }

    /// Captures the current radio access technology string for event metadata (MON-04).
    /// Returns values like "CTRadioAccessTechnologyLTE", "CTRadioAccessTechnologyNR", etc.
    ///
    /// Creates a fresh CTTelephonyNetworkInfo instance each time to avoid returning stale
    /// cached values from the long-lived `networkInfo` property. This is necessary because
    /// a single CTTelephonyNetworkInfo instance can cache the radio tech from creation time
    /// and not reflect subsequent user settings changes (e.g., switching from LTE to 5G).
    private func captureRadioTechnology() -> String? {
        let freshInfo = CTTelephonyNetworkInfo()
        return freshInfo.serviceCurrentRadioAccessTechnology?.values.first
    }

    /// Carrier name is no longer available — Apple deprecated CTCarrier in iOS 16 with no replacement.
    /// Always returns nil. Radio access technology (LTE/5G) is still available via serviceCurrentRadioAccessTechnology.
    private func captureCarrierName() -> String? {
        nil
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
    /// Radio technology captured from CTTelephonyNetworkInfo (MON-04).
    /// Carrier name captured best-effort from deprecated CTCarrier API (MON-05).
    /// Location attached from `lastLocation` if available (DAT-04, Phase 3 provides updates).
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

    // MARK: - Drop Notifications (MON-07)

    /// Schedules a local notification prompting sysdiagnose capture after a drop (MON-07).
    /// Only fires for drop events (silentFailure, pathChange to unsatisfied/requiresConnection).
    /// Uses a unique identifier per notification so multiple drops don't replace each other.
    private func scheduleDropNotification(eventType: EventType) {
        // Only notify for actual drops -- not probe successes, restorations, or gaps
        guard eventType == .silentFailure ||
              (eventType == .pathChange && (currentPathStatus == .unsatisfied || currentPathStatus == .requiresConnection)) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Cellular Drop Detected"
        content.body = eventType == .silentFailure
            ? "Silent modem failure detected. Capture sysdiagnose: Settings > Privacy > Analytics > sysdiagnose"
            : "Connectivity lost. Capture sysdiagnose: Settings > Privacy > Analytics > sysdiagnose"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "dropAlert-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
