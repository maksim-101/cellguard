import UIKit
import BackgroundTasks

/// App delegate for handling location-based relaunches and BGTaskScheduler registration.
///
/// SwiftUI apps need an AppDelegate (via @UIApplicationDelegateAdaptor) to access
/// didFinishLaunchingWithOptions, which is required to:
/// 1. Detect location-based relaunches (when iOS relaunches the terminated app
///    due to a significant location change) (DAT-03)
/// 2. Register BGTaskScheduler task identifiers (must happen before app finishes launching) (BKG-03)
///
/// The BGAppRefreshTask handler runs the probe directly via the shared monitor reference.
/// Previous approach (posting a NotificationCenter notification for SwiftUI .onReceive)
/// was broken: during background-only launches, no SwiftUI scene exists, so .onReceive
/// never fires and the task is never completed.
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {

    /// Shared reference to the ConnectivityMonitor, set by CellGuardApp.init().
    /// Used by BGAppRefreshTask handler to run probes during background-only launches
    /// where no SwiftUI view hierarchy exists.
    static var sharedMonitor: ConnectivityMonitor?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register BGTaskScheduler for supplementary background refresh (BKG-03)
        // Handler runs directly via sharedMonitor — no NotificationCenter relay needed.
        // This works regardless of whether a SwiftUI scene exists (critical for background launches).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.cellguard.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }

            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }

            Task { @MainActor in
                if let monitor = AppDelegate.sharedMonitor {
                    await monitor.runSingleProbe()
                }
                refreshTask.setTaskCompleted(success: true)
                MonitoringHealthService.scheduleAppRefresh()
            }
        }

        // Schedule the first BGAppRefreshTask now that the handler is registered.
        // Must happen here (not in CellGuardApp.init) because App.init runs before
        // didFinishLaunchingWithOptions, and submitting before registration crashes.
        MonitoringHealthService.scheduleAppRefresh()

        // Detect location-based relaunch (DAT-03)
        if launchOptions?[.location] != nil {
            UserDefaults.standard.set(true, forKey: "launchedForLocation")
        }

        return true
    }
}
