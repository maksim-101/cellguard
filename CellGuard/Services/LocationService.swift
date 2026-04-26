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

    /// Threshold in seconds above which a gap between wakes is logged as a monitoringGap event.
    /// 10 minutes (600s) -- gaps shorter than this are normal iOS scheduling behavior.
    private let gapThreshold: TimeInterval = 600

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let monitoringEnabled = "monitoringEnabled"
        static let lastActiveTimestamp = "lastActiveTimestamp"
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

        // Persist monitoring state for auto-resume after relaunch (DAT-03)
        UserDefaults.standard.set(true, forKey: DefaultsKey.monitoringEnabled)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastActiveTimestamp)
    }

    /// Stops significant location change monitoring and releases the CLServiceSession.
    @MainActor
    func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        serviceSession = nil
        UserDefaults.standard.set(false, forKey: DefaultsKey.monitoringEnabled)
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

            // 4. Update last active timestamp for next gap check
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: DefaultsKey.lastActiveTimestamp
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
    /// If the gap exceeds the threshold (10 minutes), a monitoringGap event is logged
    /// with the gap start time and duration. This allows exported data to distinguish
    /// "no drops occurred" from "the app was suspended and couldn't detect drops."
    private func detectAndLogGap() {
        let lastActive = UserDefaults.standard.double(forKey: DefaultsKey.lastActiveTimestamp)

        // First launch -- no previous timestamp to compare against
        if lastActive == 0 {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: DefaultsKey.lastActiveTimestamp
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
