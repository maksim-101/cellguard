import Network
import Observation
import Foundation
import CoreTelephony
import NetworkExtension
import UserNotifications
import SystemConfiguration
import os

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

    /// Current VPN tunnel state inferred from system proxy settings.
    /// Updated live via `captureVPNState()` from `handlePathUpdate`. Drives the dashboard's
    /// `effectiveInterfaceLabel` (VPN-02). Default `.disconnected` matches the steady "no VPN"
    /// case so the initial render is correct before the first detector call.
    private(set) var currentVPNState: VPNState = .disconnected

    /// The matched tunnel interface key (e.g. "utun3") from the most recent
    /// detectVPNInterface() scan. Set alongside `currentVPNState` so the two are always
    /// from the same probe. nil when no VPN tunnel is detected.
    private(set) var currentVPNInterface: String?

    /// Dashboard-only override: returns "VPN" when a VPN tunnel is connected or reasserting,
    /// otherwise the raw interface type's display name. Per UI-SPEC this override is ONLY
    /// consumed by DashboardView.connectivityStateCard. EventDetailView, EventListView, and
    /// JSON export all use raw interfaceType.
    var effectiveInterfaceLabel: String {
        if currentVPNState == .connected || currentVPNState == .reasserting {
            return "VPN"
        }
        return currentInterfaceType.displayName
    }

    // MARK: - Internal State for Classification

    /// Previous path status, used to detect transitions.
    private var previousPathStatus: PathStatus = .unsatisfied

    /// Previous VPN detector boolean. Used to derive .connecting / .disconnecting transients
    /// from sequential observations (08-RESEARCH.md "From boolean to 6-state").
    private var previousVPNDetectorState: Bool = false

    /// Sliding window for `.reasserting` inference: when path drops while VPN is up, set
    /// this to now+5s. Subsequent VPN-up observations within the window classify as
    /// `.reasserting` rather than `.connected`.
    private var vpnReassertingUntil: Date?

    /// Wall-clock timestamp of the most recent probe START. Set immediately after
    /// the dedup guard passes, before the URLSession await. Used by the dedup guard
    /// to suppress redundant `.probeSuccess` probes within a sliding 60-second window
    /// (POLISH-02 / D-13). A probe currently in flight blocks a second concurrent
    /// probe via this clock alone.
    private var lastProbeStartedAt: Date?

    /// Outcome of the most recent fully resolved probe. Read by the dedup guard
    /// (D-12): only `.probeSuccess` triggers suppression — `.probeFailure` and
    /// `.silentFailure` always allow the next probe to run regardless of recency
    /// (D-14: failures are the entire evidence stream and must never be suppressed).
    private var lastProbeOutcome: EventType?

    /// True while a probe is awaiting its network result. Because `runProbe()` is
    /// `@MainActor async` it is reentrant at every `await`, so without this flag a
    /// burst of triggers (rapid `logUserIncident()` calls, each clearing
    /// `lastProbeOutcome`, overlapping the 60s timer) would start several probes that
    /// all sail past the success-dedup guard and log in the same second — the
    /// duplicate-timestamp clusters seen in exports. A concurrent probe started while
    /// one is in flight is coalesced (skipped).
    private var probeInFlight = false

    /// One-shot guard for the embedded Wave 0 self-check telemetry (08-VERIFICATION-WAVE-0.md).
    /// On the first `captureVPNDetectorBool()` call per app launch we emit the full
    /// `__SCOPED__` key list and the matched prefix (or "no match") via os_log so the
    /// detection mechanism can be verified from Console.app.
    private var didEmitVPNSelfCheck: Bool = false

    /// Tracks the previous VPN tunnel boundary side for vpnStateChange events (Task 4).
    /// false = absent side (disconnected / invalid); true = present side (connecting /
    /// connected / reasserting / disconnecting). Only the absent↔present crossing is logged,
    /// not state-machine micro-transitions within the same side (e.g. connecting→connected).
    private var previousVPNBoundarySide: Bool = false

    /// Logger for VPN detector self-check telemetry. Subsystem matches the bundle id pattern
    /// used elsewhere in the project; category lets the user filter Console.app to "vpn".
    private let vpnLogger = Logger(subsystem: "com.cellguard.connectivity", category: "vpn")

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

    /// Timer that fires the GET probe every 60 seconds in foreground.
    /// Paused in background (iOS suspends timers). Phase 3 adds wake-then-probe.
    private var probeTimer: Timer?

    /// URL for the active connectivity probe. Apple's captive portal detection endpoint
    /// is lightweight, always up, and raises no privacy concerns.
    private let probeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!

    /// Timeout for each HEAD probe request. 10 seconds is generous but catches slow failures.
    private let probeTimeout: TimeInterval = 10

    /// Ceiling for a valid measured probe latency. A probe's ACTIVE duration cannot exceed
    /// probeTimeout (it would time out first), so a wall-clock latency beyond this means the app
    /// was suspended in the background mid-probe and the elapsed time includes the frozen period.
    /// Such samples are measurement artifacts (e.g. a "successful" probe reading 900+ seconds),
    /// not real network latency, so they are recorded as nil rather than poisoning the stats.
    /// Computed (not stored) so it tracks probeTimeout; the +2s absorbs scheduling slop.
    private var maxValidProbeLatencyMs: Double { (probeTimeout + 2) * 1000 }

    /// Wall-clock latency since `start` in ms, or nil if it exceeds `maxValidProbeLatencyMs`.
    /// A nil means the probe spanned a background suspension and its latency is meaningless --
    /// the probe outcome (success/failure) is still logged, only the bogus latency is dropped.
    private func validatedProbeLatencyMs(since start: Date) -> Double? {
        let ms = Date().timeIntervalSince(start) * 1000
        return ms <= maxValidProbeLatencyMs ? ms : nil
    }

    /// Interval between probe firings. 60 seconds balances detection speed with battery.
    private let probeInterval: TimeInterval = 60

    /// Confirmation URL for two-host silentFailure validation. Independent of Apple's endpoint
    /// so a stale-socket or single-host DNS fluke on the primary probe cannot trigger a
    /// false-positive silentFailure classification. Cloudflare /cdn-cgi/trace returns HTTP 200
    /// to a GET from any reachable network.
    private let confirmationURL = URL(string: "https://cloudflare.com/cdn-cgi/trace")!

    /// URL for the cellular throughput probe. Returns exactly 100 KB with no auth — deterministic
    /// for data budgeting. Cloudflare is already the trusted second probe host in confirmSilentFailure.
    /// At ~12 samples/hr × 24h × 100 KB ≈ 29 MB/day — the agreed cellular data budget.
    /// Tunable: swap this endpoint to change payload size or host.
    private let throughputProbeURL = URL(string: "https://speed.cloudflare.com/__down?bytes=102400")!

    /// Run the throughput measurement once every Nth 60s reachability cycle (≈ 5 min at N=5).
    /// Tunable: lower N means more samples and more data; raise to reduce cellular usage.
    private let throughputCycleInterval = 5

    /// Throughput below this threshold (in Kbps) is classified as .slowThroughput.
    /// 1000 Kbps = 1 Mbps is a conservative starting value for a degraded 5G NR-NSA data stall.
    /// Tunable: lower for stricter flagging, raise to reduce noise on marginal connections.
    private let slowThroughputThresholdKbps: Double = 1000

    /// Throughput below this threshold (in Kbps) is classified as .severeThroughput and COUNTS AS A
    /// DROP. 200 Kbps ≈ a 100KB transfer taking >4s — bulk data effectively unusable for web/video
    /// even though tiny reachability probes still succeed. Tunable: this is the failure/degraded line.
    private let severeThroughputThresholdKbps: Double = 200

    /// Counts completed reachability cycles to schedule the every-Nth-cycle throughput measurement.
    private var throughputCycleCounter = 0

    // MARK: - Sustained Stall Probe (call-mimic)

    /// URL for the sustained streaming probe. A one-shot HEAD/GET can't see the 1–3s mid-stream
    /// freezes that break a real-time call; a larger streamed download holds the connection open
    /// long enough to observe an inter-chunk freeze. 2 MB from Cloudflare's deterministic endpoint.
    private let sustainedProbeURL = URL(string: "https://speed.cloudflare.com/__down?bytes=2000000")!

    /// Per-chunk timeout for the sustained probe (seconds). Larger than the reachability timeout
    /// because the transfer legitimately takes several seconds; if no data arrives for this long
    /// the request errors out and we do NOT log a dataStall (ambiguous with app suspension —
    /// total death is already captured as silentFailure by the reachability probe).
    private let sustainedProbeTimeout: TimeInterval = 30

    /// A mid-stream freeze longer than this (ms) is logged as a .dataStall — the closest
    /// data-plane analog of a call freezing. 1500 ms is well past normal cellular jitter.
    private let stallThresholdMs: Double = 1500

    /// Run the sustained stall probe once every Nth reachability cycle (≈ 10 min at N=10).
    /// At 2 MB/run that is ~12 MB/hr while continuously alive (intensive mode). Tunable.
    private let stallProbeCycleInterval = 10

    /// Counts completed reachability cycles to schedule the every-Nth-cycle sustained stall probe.
    private var stallCycleCounter = 0

    /// Creates a fresh ephemeral URLSession for each probe. Per-probe sessions prevent stale
    /// HTTP keep-alive connections (caused by cellular NAT binding expiry or IP rotation) from
    /// hanging to the full 10s timeout and being misclassified as silentFailure on an otherwise
    /// healthy link. `waitsForConnectivity = false` ensures immediate failure when the path is
    /// genuinely down, which is essential for detecting silent modem failures.
    private func makeProbeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = probeTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - CoreTelephony (MON-04, MON-05)

    /// CTTelephonyNetworkInfo instance for notification registration.
    /// IMPORTANT: A single instance can return stale radio tech values. The captureRadioTechnology()
    /// method creates a fresh instance each time to ensure current values are read.
    /// This is a known behavior where the dictionary returned by serviceCurrentRadioAccessTechnology
    /// on a long-lived instance may not reflect settings changes (e.g., user switching LTE <-> 5G).
    private let networkInfo = CTTelephonyNetworkInfo()

    /// NotificationCenter observer token for radio tech changes, stored for cleanup on stop.
    private var radioTechObserver: (any NSObjectProtocol)?

    /// Last-known tech per service identifier, keyed by CoreTelephony's opaque service id.
    /// Seeded at `startMonitoring()` and refreshed on every radioTechChange, so the phantom-event
    /// fix in `setupRadioTechObserver` compares each service against ITSELF rather than against
    /// a single arbitrary-dictionary-order value. Without the launch-time seed, the first
    /// notification after launch could log a change for a service whose tech never actually moved.
    private var lastTechByService: [String: String] = [:]

    /// Retained CTCellularData instance for monitoring cellular data access restriction.
    /// The notifier closure (set in startMonitoring) populates `cellularDataRestrictedState`
    /// asynchronously; `.restrictedStateUnknown` is the value before the first callback.
    private let cellularData = CTCellularData()

    /// Current cellular data restriction state as last delivered by CTCellularData notifier.
    /// Initialized to .restrictedStateUnknown; updated on every notifier callback.
    private var cellularDataRestrictedState: CTCellularDataRestrictedState = .restrictedStateUnknown

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
        let initialRadioSnapshot = captureRadioSnapshot()
        currentRadioTechnology = initialRadioSnapshot.primaryTech
        // Seed per-service tracking at launch -- without this, the first radioTechChange
        // notification after launch could log a change for a service whose tech never actually
        // moved (there would be nothing to compare it against).
        lastTechByService = initialRadioSnapshot.techByService

        // CTCellularData: install notifier to track whether cellular data is restricted (Task 2).
        // The notifier fires immediately with the current state and again on any change. We retain
        // `cellularData` as an instance property so the notifier is not released early.
        cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            Task { @MainActor in
                self?.cellularDataRestrictedState = state
            }
        }

        // Start the 60-second GET probe cycle
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

    // MARK: - VPN Detection Self-Check (Task 5)

    /// Performs an on-demand VPN detection self-check by running the same
    /// CFNetworkCopySystemProxySettings scan as the monitoring loop and returning a
    /// human-readable result string suitable for in-app display.
    ///
    /// Result format:
    ///   "matched=utun3 (prefix utun)"   — tunnel detected
    ///   "NO MATCH — keys=[ap0, en0]"    — no tunnel keys found
    ///   "no proxy settings"             — __SCOPED__ dict unavailable
    ///
    /// The once-per-launch os_log self-check from captureVPNDetectorBool() is preserved
    /// and independent of this method; both serve different audiences (Console.app vs. UI).
    func vpnDetectionSelfCheck() -> String {
        let detection = detectVPNInterface()
        if detection.sortedKeys.isEmpty {
            return "no proxy settings"
        }
        if let mk = detection.matchedKey, let mp = detection.matchedPrefix {
            return "matched=\(mk) (prefix \(mp))"
        }
        let keyList = detection.sortedKeys.joined(separator: ", ")
        return "NO MATCH — keys=[\(keyList)]"
    }

    // MARK: - Radio Services Self-Check (Task 2)

    /// Performs an on-demand radio-services self-check, dumping the RAW CoreTelephony inputs so
    /// a single screenshot settles both on-device unknowns left open by the SDK header review:
    /// whether `dataServiceIdentifier` resolves to a real line, and whether
    /// `serviceSubscriberCellularProviders` still enumerates provisioned service keys on iOS 26.
    /// Prints only what the APIs returned -- no inference, no scanning detection (see plan
    /// `<out_of_scope>`: there is no public API for signal strength or PLMN-scan state).
    func radioServicesSelfCheck() -> String {
        let info = CTTelephonyNetworkInfo()
        let techByService = info.serviceCurrentRadioAccessTechnology ?? [:]
        let subscriberKeys = info.serviceSubscriberCellularProviders?.keys.sorted() ?? []
        let snapshot = captureRadioSnapshot()

        var lines: [String] = []

        lines.append("dataServiceIdentifier: \(info.dataServiceIdentifier ?? "(nil)")")

        if techByService.isEmpty {
            lines.append("serviceCurrentRadioAccessTechnology: (empty)")
        } else {
            for id in techByService.keys.sorted() {
                lines.append("  \(id) = \(techByService[id] ?? "(nil)")")
            }
        }

        lines.append(subscriberKeys.isEmpty
            ? "serviceSubscriberCellularProviders keys: (empty)"
            : "serviceSubscriberCellularProviders keys: \(subscriberKeys.joined(separator: ", "))")

        let primaryService = snapshot.services.first(where: \.isPrimary)
        let primaryRule = info.dataServiceIdentifier != nil ? "dataServiceIdentifier" : "sorted-key fallback"
        lines.append("Primary chosen: \(primaryService?.service ?? "(none)") (rule: \(primaryRule))")

        let unregistered = snapshot.services.filter { $0.tech == nil }.map(\.service)
        lines.append(unregistered.isEmpty
            ? "Provisioned but unregistered: (none)"
            : "Provisioned but unregistered: \(unregistered.joined(separator: ", "))")

        return lines.joined(separator: "\n")
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

    /// Logs a user-reported incident (manual marker) with the current radio/path/location
    /// snapshot. This is the ground-truth tap the user makes the instant a real-world failure
    /// happens (dropped call, dead data), giving an anchor to correlate against the automated
    /// probe and radio-transition trace. Also fires an immediate confirmation probe so the
    /// measured connectivity state right at the incident is captured alongside the marker.
    @MainActor
    func logUserIncident() async {
        logEvent(
            type: .userIncident,
            status: currentPathStatus,
            interface: currentInterfaceType,
            isExpensive: pathMonitor.currentPath.isExpensive,
            isConstrained: pathMonitor.currentPath.isConstrained,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            pathUsesCellular: pathMonitor.currentPath.usesInterfaceType(.cellular)
        )
        // Force a fresh probe at the incident moment (bypasses the dedup window by clearing the
        // last outcome) so the marker is paired with a real-time reachability measurement.
        lastProbeOutcome = nil
        await runProbe()
    }

    // MARK: - HEAD Probe (MON-02, MON-03)

    /// Performs a single GET request to Apple's captive portal to verify actual connectivity.
    ///
    /// Detects silent modem failures (MON-03): when the probe fails but NWPathMonitor still
    /// reports the path as satisfied on cellular, the modem is "attached but unreachable."
    ///
    /// Uses GET (not HEAD) so the response body can be validated. Apple's captive portal
    /// returns a body containing "Success" on a clean connection; a transparent proxy or
    /// login portal substitutes its own HTML, making the 200 response unreliable without
    /// the body check.
    ///
    /// Captures path state BEFORE awaiting the probe result to avoid the race condition
    /// where path status changes during the request (Pitfall 5 from research).
    @MainActor
    private func runProbe() async {
        // In-flight guard: collapse overlapping reentrant probes to one. Failures are never
        // suppressed by the dedup guard below, so without this a burst of triggers would log
        // N identical-timestamp events for a single moment (the export duplicate clusters).
        if probeInFlight { return }
        // POLISH-02 dedup guard (D-11..D-15): suppress only redundant successes within a
        // sliding 60s window. Failures (.probeFailure, .silentFailure) NEVER short-circuit
        // the next probe — every failure-state moment deserves fresh confirmation.
        if let started = lastProbeStartedAt,
           Date().timeIntervalSince(started) < 60,
           lastProbeOutcome == .probeSuccess {
            return
        }
        probeInFlight = true
        defer { probeInFlight = false }
        // Update probe-START clock BEFORE the await so a concurrent caller is also blocked
        // by the same window. Outcome is set AFTER each logEvent below.
        lastProbeStartedAt = Date()

        // Pitfall 5: Capture state before awaiting probe to avoid race condition
        let capturedStatus = currentPathStatus
        let capturedInterface = currentInterfaceType
        let capturedVPNState = currentVPNState
        let capturedVPNInterface = currentVPNInterface
        let capturedPathUsesCellular = pathMonitor.currentPath.usesInterfaceType(.cellular)
        // Capture live path flags and Low Power Mode before the await (Pitfall 5 race-avoidance).
        // Previously these were hardcoded to false in every probe-path logEvent call -- the bug.
        let capturedIsExpensive = pathMonitor.currentPath.isExpensive
        let capturedIsConstrained = pathMonitor.currentPath.isConstrained
        let capturedLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"

        let start = Date()

        // Fresh ephemeral session per probe: prevents stale keep-alive connections from
        // hanging to the 10s timeout after cellular NAT rotation (false-positive silentFailure).
        let session = makeProbeSession()
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            let latencyMs = validatedProbeLatencyMs(since: start)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Body validation: Apple's captive portal endpoint returns a document containing
                // "Success" on a genuine open connection. A transparent proxy or captive login
                // page returns 200 with different body text (e.g. a redirect page), which would
                // produce false-positive probeSuccess events. Require "Success" in the body.
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.contains("Success") {
                    logEvent(
                        type: .probeSuccess,
                        status: capturedStatus,
                        interface: capturedInterface,
                        isExpensive: capturedIsExpensive,
                        isConstrained: capturedIsConstrained,
                        lowPowerMode: capturedLowPowerMode,
                        pathUsesCellular: capturedPathUsesCellular,
                        probeLatencyMs: latencyMs,
                        vpnState: capturedVPNState,
                        vpnInterface: capturedVPNInterface
                    )
                    lastProbeOutcome = .probeSuccess
                } else {
                    // 200 but wrong body -- transparent proxy or captive portal intercepting.
                    logEvent(
                        type: .probeFailure,
                        status: capturedStatus,
                        interface: capturedInterface,
                        isExpensive: capturedIsExpensive,
                        isConstrained: capturedIsConstrained,
                        lowPowerMode: capturedLowPowerMode,
                        pathUsesCellular: capturedPathUsesCellular,
                        probeLatencyMs: latencyMs,
                        probeFailureReason: "unexpected body (captive portal?)",
                        vpnState: capturedVPNState,
                        vpnInterface: capturedVPNInterface
                    )
                    lastProbeOutcome = .probeFailure
                }
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logEvent(
                    type: .probeFailure,
                    status: capturedStatus,
                    interface: capturedInterface,
                    isExpensive: capturedIsExpensive,
                    isConstrained: capturedIsConstrained,
                    lowPowerMode: capturedLowPowerMode,
                    probeLatencyMs: latencyMs,
                    probeFailureReason: "HTTP \(statusCode)",
                    vpnState: capturedVPNState,
                    vpnInterface: capturedVPNInterface
                )
                lastProbeOutcome = .probeFailure
            }
        } catch {
            let latencyMs = validatedProbeLatencyMs(since: start)

            // VPN-04 BROAD trigger (user override of D-06 narrow): treat path as effectively
            // cellular when (a) NWPath reported cellular directly, OR (b) ANY non-trivial VPN
            // tunnel is up AND the underlying path uses cellular. Without (b), VPN-over-cellular
            // probe failures would be misclassified as .probeFailure because detectPrimaryInterface
            // returns .other for utun* tunnels (08-PATTERNS.md Pitfall 2).
            // .disconnecting included so a tunnel tearing down over cellular still attributes
            // probe failures to silent-modem-failure rather than probe-failure.
            let vpnIsUp = capturedVPNState == .connected
                || capturedVPNState == .reasserting
                || capturedVPNState == .connecting
                || capturedVPNState == .disconnecting
            let effectivelyCellular = (capturedInterface == .cellular)
                || (vpnIsUp && capturedPathUsesCellular)

            if capturedStatus == .satisfied && effectivelyCellular {
                // Two-host confirmation before classifying silentFailure: a stale-socket
                // or single-host fluke will only fail captive.apple.com; a genuine modem
                // failure ("attached but unreachable") fails every host. Probe an independent
                // non-Apple host and require both to fail before logging silentFailure.
                // If the confirmation host succeeds, the primary failure was a fluke →
                // log probeSuccess so the false positive is suppressed by the dedup guard
                // on the next cycle (D-12). Dedup semantics (D-11..D-15) are preserved:
                // a fluke-induced probeSuccess here is correct — connectivity is real.
                let bothFailed = await confirmSilentFailure()

                if bothFailed {
                    logEvent(
                        type: .silentFailure,
                        status: capturedStatus,
                        interface: capturedInterface,
                        isExpensive: capturedIsExpensive,
                        isConstrained: capturedIsConstrained,
                        lowPowerMode: capturedLowPowerMode,
                        pathUsesCellular: capturedPathUsesCellular,
                        probeLatencyMs: latencyMs,
                        probeFailureReason: error.localizedDescription,
                        vpnState: capturedVPNState,
                        vpnInterface: capturedVPNInterface
                    )
                    // Start tracking drop duration if not already in a drop
                    if dropStartDate == nil {
                        dropStartDate = Date()
                    }
                    lastProbeOutcome = .silentFailure
                } else {
                    // Confirmation host reachable — primary probe failure was a single-host fluke.
                    logEvent(
                        type: .probeSuccess,
                        status: capturedStatus,
                        interface: capturedInterface,
                        isExpensive: capturedIsExpensive,
                        isConstrained: capturedIsConstrained,
                        lowPowerMode: capturedLowPowerMode,
                        pathUsesCellular: capturedPathUsesCellular,
                        probeLatencyMs: latencyMs,
                        vpnState: capturedVPNState,
                        vpnInterface: capturedVPNInterface
                    )
                    lastProbeOutcome = .probeSuccess
                }
            } else {
                logEvent(
                    type: .probeFailure,
                    status: capturedStatus,
                    interface: capturedInterface,
                    isExpensive: capturedIsExpensive,
                    isConstrained: capturedIsConstrained,
                    lowPowerMode: capturedLowPowerMode,
                    probeLatencyMs: latencyMs,
                    probeFailureReason: error.localizedDescription,
                    vpnState: capturedVPNState,
                    vpnInterface: capturedVPNInterface
                )
                lastProbeOutcome = .probeFailure
            }
        }

        // Piggyback throughput measurement on the existing 60s reachability cycle.
        // Measure actual download bandwidth only on cellular and only when reachability
        // succeeded this cycle — a connectivity failure is already captured as silentFailure
        // or probeFailure, and Wi-Fi throughput is irrelevant to the cellular-modem evidence.
        // The 60s timer is the dominant caller so this is foreground-driven in practice.
        throughputCycleCounter += 1
        // Gate on pathUsesCellular, NOT interface == .cellular: under a VPN the detected interface
        // is .other (utun), so an interface check would never run the throughput probe on cellular.
        if throughputCycleCounter % throughputCycleInterval == 0
            && capturedPathUsesCellular
            && lastProbeOutcome == .probeSuccess {
            await measureThroughput(
                status: capturedStatus,
                interface: capturedInterface,
                isExpensive: capturedIsExpensive,
                isConstrained: capturedIsConstrained,
                lowPowerMode: capturedLowPowerMode,
                pathUsesCellular: capturedPathUsesCellular,
                vpnState: capturedVPNState,
                vpnInterface: capturedVPNInterface
            )
        }

        // Sustained stall probe (call-mimic): a less-frequent, heavier streamed download that
        // surfaces mid-stream freezes a one-shot probe cannot. Same gating as throughput
        // (cellular + this cycle's reachability succeeded).
        stallCycleCounter += 1
        if stallCycleCounter % stallProbeCycleInterval == 0
            && capturedPathUsesCellular
            && lastProbeOutcome == .probeSuccess {
            await measureSustainedStall(
                status: capturedStatus,
                interface: capturedInterface,
                isExpensive: capturedIsExpensive,
                isConstrained: capturedIsConstrained,
                lowPowerMode: capturedLowPowerMode,
                pathUsesCellular: capturedPathUsesCellular,
                vpnState: capturedVPNState,
                vpnInterface: capturedVPNInterface
            )
        }
    }

    /// Probes an independent host (Cloudflare) to confirm a suspected silent modem failure.
    ///
    /// Returns `true` if the confirmation host is also unreachable (both hosts failed →
    /// genuine modem failure). Returns `false` if the confirmation host responds with HTTP 200
    /// (primary probe failure was a single-host fluke → connectivity is real).
    ///
    /// Uses a fresh ephemeral session so it is not affected by the same stale socket that
    /// may have caused the primary probe to fail.
    @MainActor
    private func confirmSilentFailure() async -> Bool {
        let session = makeProbeSession()
        defer { session.finishTasksAndInvalidate() }

        do {
            let (_, response) = try await session.data(for: URLRequest(url: confirmationURL))
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return false  // Confirmation host reachable — primary failure was a fluke
            }
            return true  // Confirmation host returned non-200 — both hosts failed
        } catch {
            return true  // Confirmation host also unreachable — both hosts failed
        }
    }

    /// Fetches a fixed 100 KB payload from Cloudflare to measure cellular download throughput.
    ///
    /// Calls logEvent directly (never routes through runProbe) so its event is always written,
    /// inherently bypassing the runProbe dedup guard. Does NOT touch lastProbeOutcome or
    /// lastProbeStartedAt so it cannot extend the reachability dedup window.
    @MainActor
    private func measureThroughput(
        status: PathStatus,
        interface: InterfaceType,
        isExpensive: Bool,
        isConstrained: Bool,
        lowPowerMode: Bool,
        pathUsesCellular: Bool,
        vpnState: VPNState,
        vpnInterface: String?
    ) async {
        let session = makeProbeSession()
        defer { session.finishTasksAndInvalidate() }

        let start = Date()
        do {
            let (data, response) = try await session.data(for: URLRequest(url: throughputProbeURL))
            let elapsed = Date().timeIntervalSince(start)

            // Guard against divide-by-zero and absurdly short elapsed times producing
            // meaningless astronomical rates. Also guard non-200 responses. The upper bound
            // (elapsed <= probeTimeout + 2) drops downloads that spanned a background suspension:
            // their wall-clock includes the frozen period, so the computed kbps would be a
            // false-slow artifact and would log a spurious .slowThroughput event.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  elapsed > 0.001, elapsed <= probeTimeout + 2 else { return }

            let kbps = (Double(data.count) * 8.0) / 1000.0 / elapsed
            let eventType: EventType
            if kbps < severeThroughputThresholdKbps {
                eventType = .severeThroughput   // effectively unusable — counts as a drop
            } else if kbps < slowThroughputThresholdKbps {
                eventType = .slowThroughput     // degraded but functional — not a drop
            } else {
                eventType = .probeSuccess
            }
            logEvent(
                type: eventType,
                status: status,
                interface: interface,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode,
                pathUsesCellular: pathUsesCellular,
                throughputKbps: kbps,
                vpnState: vpnState,
                vpnInterface: vpnInterface
            )
        } catch {
            // A throughput fetch failure is not a connectivity failure — this cycle's
            // reachability probe already succeeded. Log nothing to avoid spurious events.
            return
        }
    }

    /// Streams a larger payload and measures the longest gap between received data chunks.
    /// A long mid-stream freeze on an otherwise-reachable link is the closest data-plane analog
    /// of a real-time call freezing — logged as .dataStall (a drop).
    ///
    /// Only logs on CLEAN completion (no error): a request that times out is ambiguous with an
    /// app suspension spanning the transfer, and a total link death is already captured as
    /// silentFailure by the reachability probe. This isolates the "froze for N seconds, then
    /// recovered" signature.
    @MainActor
    private func measureSustainedStall(
        status: PathStatus,
        interface: InterfaceType,
        isExpensive: Bool,
        isConstrained: Bool,
        lowPowerMode: Bool,
        pathUsesCellular: Bool,
        vpnState: VPNState,
        vpnInterface: String?
    ) async {
        let tracker = StallTracker()
        let result = await tracker.run(url: sustainedProbeURL, timeout: sustainedProbeTimeout)

        guard result.error == nil, result.totalBytes > 0, result.maxStallMs > stallThresholdMs else { return }

        logEvent(
            type: .dataStall,
            status: status,
            interface: interface,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            lowPowerMode: lowPowerMode,
            pathUsesCellular: pathUsesCellular,
            probeFailureReason: "stream froze mid-transfer",
            dropDuration: result.maxStallMs / 1000,
            vpnState: vpnState,
            vpnInterface: vpnInterface
        )
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
        ) { [weak self] notification in
            // The notification's `object` IS the service identifier String whose radio tech
            // changed (SDK-confirmed: CTServiceRadioAccessTechnologyDidChangeNotification header
            // doc). This is exactly what the old `.values.first` read discarded, which made the
            // old/new comparison an arbitrary-dictionary-iteration-order coin flip whenever two
            // SIM services were present. No CoreTelephony call needed to read the notification
            // object, so this can stay outside the CoreTelephony reads below.
            let changedService = notification.object as? String
            Task { @MainActor in
                guard let self else { return }

                let snapshot = self.captureRadioSnapshot()
                let newTechForChangedService = changedService.flatMap { snapshot.techByService[$0] }

                let suppress: Bool
                if let svc = changedService {
                    // Phantom-event fix: suppress only when THIS SPECIFIC service's tech is
                    // unchanged, comparing it against ITSELF (lastTechByService[svc]) instead of
                    // the old single-value currentRadioTechnology. An iteration-order flip
                    // between two lines can no longer masquerade as a transition, because we now
                    // compare a line against itself.
                    suppress = self.lastTechByService[svc] == newTechForChangedService
                } else {
                    // Not expected per the header doc, but if the identifier is somehow absent,
                    // fall back to comparing the primary tech (today's pre-fix behavior) rather
                    // than dropping the event: a logged event with a nil radioChangeService is
                    // recoverable evidence; a dropped event is not.
                    suppress = self.currentRadioTechnology == snapshot.primaryTech
                }
                // Update tracking regardless of suppression so the next notification compares
                // against the current state, not a stale one.
                self.lastTechByService = snapshot.techByService
                self.currentRadioTechnology = snapshot.primaryTech
                guard !suppress else { return }

                // High-resolution radio-layer trace: log every actual transition (incl. signal
                // acquisition/loss). This is the near-free oscilloscope for baseband instability —
                // an NRNSA→LTE flip is the EN-DC/SCG-failure fingerprint that coincides with the
                // call-drop window. Not a drop, so no notification.
                self.logEvent(
                    type: .radioTechChange,
                    status: self.currentPathStatus,
                    interface: self.currentInterfaceType,
                    isExpensive: self.pathMonitor.currentPath.isExpensive,
                    isConstrained: self.pathMonitor.currentPath.isConstrained,
                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    radioChangeService: changedService
                )
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

    /// Result of a single `captureRadioSnapshot()` call: every provisioned service's state plus
    /// the resolved primary line's tech, so callers needing only the primary (the vast majority)
    /// don't need a second CoreTelephony read.
    private struct RadioCapture {
        let services: [RadioServiceSnapshot]
        let primaryTech: String?
        let techByService: [String: String]
    }

    /// Captures the full per-service (multi-SIM / DSDS) radio state in one CoreTelephony read
    /// for event metadata (MON-04, DSDS-01/02/03). Replaces `captureRadioTechnology()` -- the
    /// old `serviceCurrentRadioAccessTechnology?.values.first` read sampled an ARBITRARY
    /// dictionary entry whenever two SIM services were present (Dictionary.values has no defined
    /// ordering), corrupting both the stored radioTechnology and the phantom-transition
    /// classification in `setupRadioTechObserver`.
    ///
    /// Creates a fresh CTTelephonyNetworkInfo instance each time to avoid returning stale cached
    /// values from the long-lived `networkInfo` property -- a single instance can cache the
    /// radio tech from creation time and miss subsequent settings changes (e.g. LTE <-> 5G).
    private func captureRadioSnapshot() -> RadioCapture {
        let info = CTTelephonyNetworkInfo()
        let techByService = info.serviceCurrentRadioAccessTechnology ?? [:]

        // Provisioned-service enumeration: serviceSubscriberCellularProviders is deprecated
        // (iOS 16.4, no replacement) but its KEYS still enumerate provisioned service slots --
        // only its CTCarrier VALUES are junk post-16.4 and must never be read. The resulting
        // deprecation warning is expected and accepted (see plan sdk_facts #3).
        var provisionedIDs = Set(techByService.keys)
        if let subscriberKeys = info.serviceSubscriberCellularProviders?.keys {
            provisionedIDs.formUnion(subscriberKeys)
        }
        // Belt-and-braces: never let the data line silently drop out of the list even if both
        // dictionaries above somehow omit it.
        if let dataID = info.dataServiceIdentifier {
            provisionedIDs.insert(dataID)
        }
        // Sorting is what makes the union's iteration order STABLE across calls.
        let sortedIDs = provisionedIDs.sorted()

        // Primary-line selection, in priority order:
        // 1. dataServiceIdentifier -- iOS's own authoritative answer to "which line carries
        //    data" (public, iOS 13+, not deprecated). Used whenever non-nil.
        // 2. Fallback: the lowest service identifier in the sorted union. Arbitrary but STABLE --
        //    the same line is chosen on every call, so the tie-break itself can never manufacture
        //    a phantom transition. A future reader must know the primary is a guess in this
        //    branch (see radioServicesSelfCheck(), which reports which rule fired).
        let primary = info.dataServiceIdentifier ?? sortedIDs.first

        let services = sortedIDs.map { id in
            // A missing entry in techByService means the service is provisioned but registered
            // on NO network (Apple's documented absence semantics) -- recorded as an explicit
            // nil `tech`, never omitted from the array.
            RadioServiceSnapshot(service: id, tech: techByService[id], isPrimary: id == primary)
        }
        let primaryTech = primary.flatMap { techByService[$0] }

        return RadioCapture(services: services, primaryTech: primaryTech, techByService: techByService)
    }

    /// Carrier name is no longer available — Apple deprecated CTCarrier in iOS 16 with no replacement.
    /// Always returns nil. Radio access technology (LTE/5G) is still available via serviceCurrentRadioAccessTechnology.
    private func captureCarrierName() -> String? {
        nil
    }

    /// Reads the current CTCellularData restriction state as a human-readable string.
    /// Returns "restricted", "notRestricted", or "unknown" (the .restrictedStateUnknown
    /// case, which persists until the cellularDataRestrictionDidUpdateNotifier fires for
    /// the first time after startMonitoring()).
    private func captureCellularDataRestriction() -> String {
        switch cellularDataRestrictedState {
        case .restricted: return "restricted"
        case .notRestricted: return "notRestricted"
        case .restrictedStateUnknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    /// Captures the current Wi-Fi SSID if available.
    /// Returns nil when not on Wi-Fi, missing entitlement, or in restricted background context.
    private func captureWifiSSID() async -> String? {
        let network = await NEHotspotNetwork.fetchCurrent()
        return network?.ssid
    }

    /// Shared VPN detection core: reads CFNetworkCopySystemProxySettings.__SCOPED__ once
    /// and returns all keys plus the first matched tunnel interface key and its matching prefix.
    ///
    /// Why CFNetworkCopySystemProxySettings and not the NEVPNManager API: that API is
    /// scoped to the calling app's own VPN configurations only. CellGuard owns no VPN config,
    /// so it would always return .invalid/.disconnected for third-party tunnels (Mullvad,
    /// WireGuard, ProtonVPN, Settings VPN profiles). See 08-RESEARCH.md "Detection Mechanism".
    ///
    /// Returns `sortedKeys: []` when __SCOPED__ is unavailable (no active proxy settings).
    /// Idempotent for a given system state — safe to call multiple times per path update.
    private func detectVPNInterface() -> (sortedKeys: [String], matchedKey: String?, matchedPrefix: String?) {
        guard let cfDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = cfDict["__SCOPED__"] as? [String: Any] else {
            return (sortedKeys: [], matchedKey: nil, matchedPrefix: nil)
        }
        let sortedKeys = scoped.keys.sorted()
        let prefixes = ["utun", "ipsec", "tap", "tun", "ppp"]
        for key in scoped.keys {
            let lowered = key.lowercased()
            if let hit = prefixes.first(where: { lowered.hasPrefix($0) }) {
                return (sortedKeys: sortedKeys, matchedKey: key, matchedPrefix: hit)
            }
        }
        return (sortedKeys: sortedKeys, matchedKey: nil, matchedPrefix: nil)
    }

    /// Detects whether ANY system-wide VPN tunnel is registered, using the shared
    /// detectVPNInterface() probe. On the first call per app launch, emits a one-shot
    /// os_log dump of the full __SCOPED__ key list and matched prefix (or "no match").
    /// This is the embedded Wave 0 device verification (08-VERIFICATION-WAVE-0.md).
    private func captureVPNDetectorBool() -> Bool {
        let detection = detectVPNInterface()
        if !didEmitVPNSelfCheck {
            didEmitVPNSelfCheck = true
            if detection.sortedKeys.isEmpty {
                vpnLogger.info("VPN self-check: __SCOPED__ unavailable (no proxy settings)")
            } else {
                let allKeys = detection.sortedKeys.joined(separator: ", ")
                if let mk = detection.matchedKey, let mp = detection.matchedPrefix {
                    vpnLogger.info("VPN self-check: keys=[\(allKeys, privacy: .public)] matched=\(mk, privacy: .public) prefix=\(mp, privacy: .public)")
                } else {
                    vpnLogger.info("VPN self-check: keys=[\(allKeys, privacy: .public)] matched=NO MATCH")
                }
            }
        }
        return detection.matchedKey != nil
    }

    /// Maps the detector boolean to the 6-state VPNState enum using edge-transition inference
    /// plus a 5-second `.reasserting` window. Called from `logEvent` (sync, outside Task) and
    /// from `handlePathUpdate` (live binding refresh).
    ///
    /// Inference rules (08-RESEARCH.md lines 182-189):
    ///   true  + true  + (in reassert window AND path satisfied) -> .reasserting
    ///   true  + true                                            -> .connected
    ///   true  + false                                           -> .connecting (transient edge)
    ///   false + true                                            -> .disconnecting (transient edge)
    ///   false + false                                           -> .disconnected
    private func captureVPNState() -> VPNState {
        let now = captureVPNDetectorBool()
        let prev = previousVPNDetectorState
        let pathSatisfied = currentPathStatus == .satisfied

        let result: VPNState
        if now && prev {
            if let until = vpnReassertingUntil, until > Date(), pathSatisfied {
                result = .reasserting
            } else {
                result = .connected
            }
        } else if now && !prev {
            result = .connecting
        } else if !now && prev {
            result = .disconnecting
        } else {
            result = .disconnected
        }

        previousVPNDetectorState = now
        return result
    }

    // MARK: - Path Update Handling

    /// Processes a raw NWPath update: maps status/interface, guards initial callback,
    /// and debounces rapid changes before classification.
    @MainActor
    private func handlePathUpdate(_ path: Network.NWPath) {
        let newStatus = mapPathStatus(path.status)
        let newInterface = detectPrimaryInterface(path)
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Pitfall 1: The initial NWPathMonitor callback reports current state,
        // not a transition. Capture it silently without logging an event.
        if isInitialUpdate {
            previousPathStatus = newStatus
            previousInterfaceType = newInterface
            currentPathStatus = newStatus
            currentInterfaceType = newInterface
            // Seed the VPN edge-detector with the tunnel state observed AT LAUNCH so an
            // already-established VPN (e.g. Tailscale connected before the app started) is
            // classified .connected on first sighting -- not a spurious false->true .connecting
            // edge for a connection the app never witnessed begin. Without this seed,
            // previousVPNDetectorState starts false; because currentVPNState only refreshes on
            // path changes, a stable post-launch path would leave every probe reporting the stale
            // .connecting. Transitions that occur WHILE the app runs (off->on, on->off) still
            // register as .connecting/.disconnecting -- those are genuine observed edges.
            previousVPNDetectorState = captureVPNDetectorBool()
            currentVPNState = captureVPNState()
            currentVPNInterface = detectVPNInterface().matchedKey
            isInitialUpdate = false
            return
        }

        // Refresh live VPN state for dashboard binding (VPN-02). Also seed the reasserting-window
        // flag when a path drop happens while VPN is up. The detector boolean is read once here
        // and passed through captureVPNState() so the per-tick edge transition is registered
        // exactly once.
        let detectorNow = captureVPNDetectorBool()
        if detectorNow && newStatus == .unsatisfied {
            // Path dropped while VPN registered -- start a 5-second reassertion window
            // (only label .reasserting later if path returns to .satisfied; Pitfall 3 in RESEARCH).
            vpnReassertingUntil = Date().addingTimeInterval(5)
        }
        // captureVPNState() will call captureVPNDetectorBool() a second time, but that is fine:
        // the boolean is idempotent for a given system state, and previousVPNDetectorState only
        // advances inside captureVPNState(). Restore prev so the state machine sees the correct
        // (prev, now) pair we just observed.
        _ = detectorNow
        currentVPNState = captureVPNState()
        // Set currentVPNInterface alongside currentVPNState so both are from the same scan tick.
        currentVPNInterface = detectVPNInterface().matchedKey

        // VPN boundary detection (Task 4): log a vpnStateChange event only when the tunnel
        // crosses the absent↔present boundary. "absent" = disconnected or invalid (no active
        // tunnel); "present" = connecting / connected / reasserting / disconnecting (a tunnel
        // negotiation or teardown is in progress or complete). This avoids logging spam for
        // micro-transitions within the same boundary side (e.g. connecting→connected).
        // vpnStateChange is NOT a drop — scheduleDropNotification ignores it because its guard
        // only matches silentFailure and pathChange-to-unsatisfied.
        let vpnIsPresent = currentVPNState != .disconnected && currentVPNState != .invalid
        if vpnIsPresent != previousVPNBoundarySide {
            previousVPNBoundarySide = vpnIsPresent
            logEvent(
                type: .vpnStateChange,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode,
                vpnState: currentVPNState,
                vpnInterface: currentVPNInterface
            )
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
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode
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
        isConstrained: Bool,
        lowPowerMode: Bool
    ) {
        // Case 1 -- Overt drop: path was satisfied, now unsatisfied or requiresConnection
        if previousPathStatus == .satisfied && (newStatus == .unsatisfied || newStatus == .requiresConnection) {
            dropStartDate = Date()
            // Record the interface that was LOST, not the post-drop interface. On an overt drop the
            // path has no available interfaces, so detectPrimaryInterface returns .unknown -- which
            // would make every cellular and Wi-Fi drop indistinguishable. previousInterfaceType is the
            // interface we were connected on, letting drop classification attribute the loss to cellular
            // vs a Wi-Fi handover gap (see isDropEvent in DropClassification.swift).
            logEvent(
                type: .pathChange,
                status: newStatus,
                interface: previousInterfaceType,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode
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
                lowPowerMode: lowPowerMode,
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
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode
            )
        }
        // Case 4 -- Other meaningful transition: any remaining status or interface change
        else if newStatus != previousPathStatus || newInterface != previousInterfaceType {
            logEvent(
                type: .pathChange,
                status: newStatus,
                interface: newInterface,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode
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
    private func mapPathStatus(_ status: Network.NWPath.Status) -> PathStatus {
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
    private func detectPrimaryInterface(_ path: Network.NWPath) -> InterfaceType {
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
    ///
    /// `vpnState` and `vpnInterface` callers from `runProbe` pass pre-await snapshots to avoid
    /// race conditions (Pitfall 5). Transition callers omit both and we read from `currentVPN*`.
    private func logEvent(
        type: EventType,
        status: PathStatus,
        interface: InterfaceType,
        isExpensive: Bool,
        isConstrained: Bool,
        lowPowerMode: Bool = false,
        pathUsesCellular: Bool? = nil,
        probeLatencyMs: Double? = nil,
        throughputKbps: Double? = nil,
        probeFailureReason: String? = nil,
        dropDuration: Double? = nil,
        vpnState: VPNState? = nil,
        vpnInterface: String? = nil,
        radioChangeService: String? = nil
    ) {
        // Heartbeat (gap-accounting fix): every logged event proves the app was alive and
        // monitoring at this instant. LocationService.detectAndLogGap measures now − lastActive,
        // so updating it here — on every probe/path event, not just location wakes — is what keeps
        // monitoringGap durations from overcounting time the app was actually awake and probing.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDefaultsKeys.lastActiveTimestamp)

        // Capture synchronous metadata outside the Task (D-09: VPN detector must be called
        // synchronously to match Phase 7's wifiSSID precedent and avoid actor-hop staleness).
        // Single CoreTelephony read for this event -- captureRadioSnapshot() replaces the old
        // captureRadioTechnology() call and supplies both the primary-line tech and every
        // provisioned service's state from the same read.
        let radio = captureRadioSnapshot()
        let carrier = captureCarrierName()
        let cellularRestriction = captureCellularDataRestriction()
        let location = lastLocation
        // If a caller already snapshotted the state (i.e. runProbe), use it; otherwise
        // capture fresh so transition events get the live state.
        let resolvedVPNState = vpnState ?? captureVPNState()
        // Same pattern for vpnInterface: use the pre-await snapshot if provided, otherwise
        // read from currentVPNInterface (set alongside currentVPNState in handlePathUpdate).
        let resolvedVPNInterface = vpnInterface ?? currentVPNInterface
        // Use the caller's pre-await snapshot when provided (probe/throughput paths capture it before
        // the await to avoid the Pitfall 5 race); otherwise read the live path (path-change events).
        // usesInterfaceType(.cellular) is true for cellular even through a VPN tunnel, unlike isExpensive.
        let resolvedUsesCellular = pathUsesCellular ?? pathMonitor.currentPath.usesInterfaceType(.cellular)

        Task {
            let ssid = await captureWifiSSID()

            let event = ConnectivityEvent(
                eventType: type,
                pathStatus: status,
                interfaceType: interface,
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                lowPowerMode: lowPowerMode,
                pathUsesCellular: resolvedUsesCellular,
                radioTechnology: radio.primaryTech,
                carrierName: carrier,
                radioServicesJSON: RadioServiceSnapshot.encode(radio.services),
                radioChangeService: radioChangeService,
                cellularDataRestricted: cellularRestriction,
                wifiSSID: ssid,
                vpnState: resolvedVPNState,
                vpnInterface: resolvedVPNInterface,
                probeLatencyMs: probeLatencyMs,
                throughputKbps: throughputKbps,
                probeFailureReason: probeFailureReason,
                latitude: location?.latitude,
                longitude: location?.longitude,
                locationAccuracy: location?.accuracy,
                dropDurationSeconds: dropDuration
            )

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
              eventType == .severeThroughput ||
              (eventType == .pathChange && (currentPathStatus == .unsatisfied || currentPathStatus == .requiresConnection)) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Cellular Drop Detected"
        switch eventType {
        case .silentFailure:
            content.body = "Silent modem failure detected. Capture sysdiagnose: Settings > Privacy > Analytics > sysdiagnose"
        case .severeThroughput:
            content.body = "Severe throughput degradation — data effectively stalled on 5G/cellular. Capture sysdiagnose: Settings > Privacy > Analytics > sysdiagnose"
        default:
            content.body = "Connectivity lost. Capture sysdiagnose: Settings > Privacy > Analytics > sysdiagnose"
        }
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

// MARK: - Sustained Stall Tracking Delegate

/// Streams a download via URLSessionDataDelegate and records the longest gap between received
/// data chunks (the "mid-stream freeze"). A completion-handler data task accumulates data without
/// firing per-chunk delegate callbacks, so a delegate-driven task is required to time chunks.
///
/// `@unchecked Sendable`: all mutable state is touched only on the session's serial delegate
/// queue (chunk callbacks) and read once after the task completes — no concurrent access.
private final class StallTracker: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var lastChunkAt: Date?
    private var maxStallMs: Double = 0
    private var totalBytes = 0
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Runs the streamed download and returns the longest inter-chunk gap, bytes received, and any error.
    func run(url: URL, timeout: TimeInterval) async -> (maxStallMs: Double, totalBytes: Int, error: Error?) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            session.dataTask(with: url).resume()
        }
        session.finishTasksAndInvalidate()
        return (maxStallMs, totalBytes, failure)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let now = Date()
        if let last = lastChunkAt {
            let gap = now.timeIntervalSince(last) * 1000
            if gap > maxStallMs { maxStallMs = gap }
        }
        lastChunkAt = now
        totalBytes += data.count
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        failure = error
        continuation?.resume()
        continuation = nil
    }
}
