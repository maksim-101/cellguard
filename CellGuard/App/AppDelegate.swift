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
/// The BGAppRefreshTask handler posts a notification because AppDelegate does not own
/// the ConnectivityMonitor or LocationService -- CellGuardApp observes this notification
/// and routes the task to the appropriate service.
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register BGTaskScheduler for supplementary background refresh (BKG-03)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.cellguard.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            // Post notification for CellGuardApp to handle with its service references
            NotificationCenter.default.post(
                name: .init("com.cellguard.handleRefresh"),
                object: refreshTask
            )
        }

        // Detect location-based relaunch (DAT-03)
        // When iOS relaunches the app due to a significant location change,
        // the launch options contain the .location key. This flag tells
        // CellGuardApp to immediately restart monitoring.
        if launchOptions?[.location] != nil {
            UserDefaults.standard.set(true, forKey: "launchedForLocation")
        }

        return true
    }
}
