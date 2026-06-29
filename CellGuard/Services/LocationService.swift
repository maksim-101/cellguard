import CoreLocation
import Observation
import Foundation
import UIKit

/// Manages significant location change monitoring and CLServiceSession lifecycle
/// for persistent background execution.
///
/// This is the primary mechanism that keeps CellGuard running in the background
/// indefinitely (BKG-01, BKG-05). When iOS terminates the app, a significant
/// location change (~500m movement via cell tower triangulation) relaunches it.
///
/// On each location wake:
/// 1. Updates ConnectivityMonitor with the new location (DAT-04)
/// 2. Detects and logs any monitoring gap since last wake (DAT-05)
/// 3. Triggers a single connectivity probe (wake-then-probe pattern)
/// 4. Updates the lastActiveTimestamp for the next gap check
///
/// CLServiceSession (iOS 18+) is retained for the entire monitoring lifetime
/// to ensure background location delivery is not silently dropped (BKG-02).
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Properties

    /// The location manager instance that handles significant location changes.
    private let locationManager = CLLocationManager()

    /// Retained CLServiceSession for iOS 18+ background location delivery (BKG-02).
    /// Without holding this session, background location updates may silently stop.
    private var serviceSession: CLServiceSession?

    /// Current authorization status, updated via delegate callback.
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The connectivity monitor to update with location data and trigger probes.
    private let monitor: ConnectivityMonitor

    /// The event store for persisting monitoring gap events.
    private let eventStore: EventStore

    /// Threshold in seconds above which a gap between probes is logged as a monitoringGap event.
    /// In normal mode 10 minutes (600s) — shorter gaps are just iOS discretionary scheduling
    /// (BGAppRefresh runs ~every 15 min). In intensive mode the 60s timer should never miss for
    /// long, so a 4-minute hole already means keep-alive failed and is worth recording.
    private var gapThreshold: TimeInterval {
        UserDefaults.standard.bool(forKey: AppDefaultsKeys.intensiveCaptureEnabled) ? 240 : 600
    }

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let monitoringEnabled = "monitoringEnabled"
    }

    // MARK: - Initializer

    /// Creates a LocationService with injected dependencies.
    /// - Parameters:
    ///   - monitor: The ConnectivityMonitor to receive location updates and probe triggers.
    ///   - eventStore: The EventStore for persisting monitoring gap events.
    init(monitor: ConnectivityMonitor, eventStore: EventStore) {
        self.monitor = monitor
        self.eventStore = eventStore
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Starts significant location change monitoring and creates a CLServiceSession.
    ///
    /// Requests "Always" location authorization (required for background delivery),
    /// creates a CLServiceSession (iOS 18+ requirement), and begins monitoring
    /// significant location changes. Persists monitoring state in UserDefaults
    /// so it can be auto-resumed after app relaunch.
    @MainActor
    func startMonitoring() {
        // Create CLServiceSession for iOS 18+ background delivery (BKG-02)
        serviceSession = CLServiceSession(authorization: .always)

        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()

        // Honor a previously-enabled intensive capture session across relaunches.
        if UserDefaults.standard.bool(forKey: AppDefaultsKeys.intensiveCaptureEnabled) {
            startIntensiveLocationUpdates()
        }

        // Persist monitoring state for auto-resume after relaunch (DAT-03)
        UserDefaults.standard.set(true, forKey: DefaultsKey.monitoringEnabled)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDefaultsKeys.lastActiveTimestamp)
    }

    /// Stops significant location change monitoring and releases the CLServiceSession.
    @MainActor
    func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        stopIntensiveLocationUpdates()
        serviceSession = nil
        UserDefaults.standard.set(false, forKey: DefaultsKey.monitoringEnabled)
    }

    // MARK: - Intensive Capture Mode (keep-alive)

    /// Enables or disables continuous low-accuracy location keep-alive.
    ///
    /// The failure clusters in the field were all stationary-at-home: significant-location-change
    /// never wakes the app when the user doesn't move, so the 60s probe timer is suspended exactly
    /// when the modem misbehaves. An active continuous-location session keeps the process alive in
    /// the background (legitimate declared `location` background mode), letting the timer keep
    /// probing. Low accuracy (3km, cell-tower-based) keeps the battery cost modest.
    @MainActor
    func setIntensiveCapture(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AppDefaultsKeys.intensiveCaptureEnabled)
        guard UserDefaults.standard.bool(forKey: DefaultsKey.monitoringEnabled) else { return }
        if enabled {
            startIntensiveLocationUpdates()
        } else {
            stopIntensiveLocationUpdates()
        }
    }

    /// Whether intensive capture is currently enabled (persisted).
    var intensiveCaptureEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppDefaultsKeys.intensiveCaptureEnabled)
    }

    @MainActor
    private func startIntensiveLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
    }

    @MainActor
    private func stopIntensiveLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - CLLocationManagerDelegate

    /// Called when the device moves ~500m (significant location change).
    /// This is the primary background wake handler -- runs the wake-then-probe pattern.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            // 1. Update ConnectivityMonitor with new location (DAT-04)
            monitor.updateLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy
            )

            // 2. Detect and log any monitoring gap (DAT-05)
            detectAndLogGap()

            // 3. Run a single connectivity probe (wake-then-probe pattern)
            await monitor.runSingleProbe()

            // 4. Update last active timestamp for next gap check. (runProbe above also writes
            //    this on every event; writing it here too keeps wakes that log nothing honest.)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: AppDefaultsKeys.lastActiveTimestamp
            )

            // 5. NEW (POLISH-01 / D-08): record a background-wake-only timestamp. This is
            //    the "is the app still alive in the background?" signal surfaced by
            //    HealthDetailSheet's live ticker. Foreground location callbacks do NOT
            //    count — they would mask the diagnostic.
            if UIApplication.shared.applicationState != .active {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: AppDefaultsKeys.lastBackgroundWakeTimestamp
                )
            }
        }
    }

    /// Called when location authorization changes. Updates the tracked status.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Gap Detection (DAT-05)

    /// Detects monitoring gaps by comparing the current time to the last recorded
    /// active timestamp in UserDefaults.
    ///
    /// If the gap exceeds the threshold, a monitoringGap event is logged with the gap start
    /// time and duration. This allows exported data to distinguish "no drops occurred" from
    /// "the app was suspended and couldn't detect drops."
    ///
    /// `internal` (not private) so it can also be called on foreground return (ContentView) and
    /// on BGAppRefresh wake (AppDelegate) — not only on location wakes. That closes the case where
    /// the app slept all evening while stationary and the gap was only noticed on the next move.
    func detectAndLogGap() {
        let lastActive = UserDefaults.standard.double(forKey: AppDefaultsKeys.lastActiveTimestamp)

        // First launch -- no previous timestamp to compare against
        if lastActive == 0 {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: AppDefaultsKeys.lastActiveTimestamp
            )
            return
        }

        let now = Date().timeIntervalSince1970
        let gap = now - lastActive

        if gap > gapThreshold {
            let gapEvent = ConnectivityEvent(
                timestamp: Date(timeIntervalSince1970: lastActive), // Gap START time
                eventType: .monitoringGap,
                pathStatus: .unsatisfied, // Unknown during gap
                interfaceType: .unknown,
                dropDurationSeconds: gap // Reuse for gap duration
            )
            Task {
                try? await eventStore.insertEvent(gapEvent)
            }
        }
    }
}
