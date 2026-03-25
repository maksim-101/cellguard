import Observation
import Foundation
import CoreLocation
import UIKit
import BackgroundTasks

/// Aggregates system conditions (Low Power Mode, Background App Refresh status,
/// location authorization) into a single health enum for the monitoring subsystem.
///
/// The caller provides an `onConditionChanged` closure via `startObserving(onConditionChanged:)`
/// that is invoked whenever a system condition changes. The caller is responsible for
/// calling `evaluate(isMonitoring:locationAuth:backgroundRefresh:)` inside that closure
/// with current values. This keeps MonitoringHealthService decoupled from services it
/// does not own (LocationService, ConnectivityMonitor) while still enabling real-time
/// health updates (BKG-04).
@Observable
final class MonitoringHealthService {

    // MARK: - Nested Types

    enum Health: Equatable {
        case active
        case degraded(reasons: [DegradedReason])
        case paused
    }

    enum DegradedReason: String, CaseIterable {
        case lowPowerMode = "Low Power Mode is active"
        case backgroundRefreshDisabled = "Background App Refresh is disabled"
        case locationWhenInUse = "Location set to 'While Using'"
        case locationDenied = "Location access denied"

        /// User-facing instruction for resolving this degraded condition.
        var fixInstruction: String {
            switch self {
            case .lowPowerMode:
                "Turn off Low Power Mode in Settings > Battery."
            case .backgroundRefreshDisabled:
                "Enable in Settings > General > Background App Refresh."
            case .locationWhenInUse:
                "Change to 'Always' in Settings > CellGuard > Location."
            case .locationDenied:
                "Grant location access in Settings > CellGuard > Location."
            }
        }
    }

    // MARK: - Properties

    /// Current aggregated health status. Updated by `evaluate()`.
    private(set) var health: Health = .paused

    /// Stored NotificationCenter observer tokens for cleanup.
    private var observers: [Any] = []

    /// Callback invoked when a system condition changes, so the caller can re-evaluate health.
    private var onConditionChanged: (() -> Void)?

    // MARK: - Health Evaluation

    /// Evaluates current system conditions and updates the `health` property.
    ///
    /// - Parameters:
    ///   - isMonitoring: Whether the monitoring subsystem is actively running.
    ///   - locationAuth: Current CLLocationManager authorization status.
    ///   - backgroundRefresh: Current UIApplication background refresh status.
    func evaluate(
        isMonitoring: Bool,
        locationAuth: CLAuthorizationStatus,
        backgroundRefresh: UIBackgroundRefreshStatus
    ) {
        guard isMonitoring else {
            health = .paused
            return
        }

        var reasons: [DegradedReason] = []

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            reasons.append(.lowPowerMode)
        }

        if backgroundRefresh != .available {
            reasons.append(.backgroundRefreshDisabled)
        }

        if locationAuth == .authorizedWhenInUse {
            reasons.append(.locationWhenInUse)
        }

        if locationAuth == .denied || locationAuth == .restricted {
            reasons.append(.locationDenied)
        }

        health = reasons.isEmpty ? .active : .degraded(reasons: reasons)
    }

    // MARK: - System Condition Observation

    /// Begins observing system condition changes (Low Power Mode, Background App Refresh).
    ///
    /// When a condition changes, the provided closure is called on the main thread so the
    /// caller can re-evaluate health with current inputs. This is critical for BKG-04:
    /// when Low Power Mode toggles while the app is foregrounded, the health status bar
    /// must update immediately.
    ///
    /// - Parameter onConditionChanged: Closure called on the main thread when a system
    ///   condition changes. The caller should call `evaluate()` inside this closure.
    func startObserving(onConditionChanged: @escaping () -> Void) {
        self.onConditionChanged = onConditionChanged

        // Observe Low Power Mode changes
        let powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onConditionChanged?()
            }
        }
        observers.append(powerObserver)

        // Observe Background App Refresh status changes
        let refreshObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.backgroundRefreshStatusDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onConditionChanged?()
            }
        }
        observers.append(refreshObserver)
    }

    /// Stops observing system condition changes and removes all NotificationCenter observers.
    func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        onConditionChanged = nil
    }

    // MARK: - BGAppRefreshTask Scheduling

    /// Schedules the next BGAppRefreshTask for supplementary background wake.
    ///
    /// Uses a 15-minute minimum interval. The actual wake time is system-discretionary
    /// and may be longer. This is a supplementary mechanism — significant location changes
    /// are the primary background keep-alive.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.cellguard.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
}
