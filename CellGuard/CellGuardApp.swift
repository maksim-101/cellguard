import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct CellGuardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer
    @State private var monitor: ConnectivityMonitor
    @State private var locationService: LocationService
    @State private var healthService = MonitoringHealthService()
    @State private var profileService = ProvisioningProfileService()

    init() {
        let container = try! ModelContainer(for: ConnectivityEvent.self)
        self.container = container
        let store = EventStore(modelContainer: container)
        let monitor = ConnectivityMonitor(eventStore: store)
        _monitor = State(initialValue: monitor)
        let locationService = LocationService(monitor: monitor, eventStore: store)
        _locationService = State(initialValue: locationService)

        // Auto-resume monitoring immediately during init (DAT-03).
        // This is critical for background relaunches: when iOS relaunches the app
        // due to a significant location change, no UI scene is created, so .onAppear
        // never fires. Starting monitoring here ensures it runs regardless of whether
        // the launch is foreground or background.
        if UserDefaults.standard.bool(forKey: "monitoringEnabled") {
            monitor.startMonitoring()
            locationService.startMonitoring()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitor)
                .environment(locationService)
                .environment(healthService)
                .environment(profileService)
                .onAppear {
                    profileService.loadProfile()

                    // Start observing system condition changes (BKG-04).
                    // The onConditionChanged closure is called by MonitoringHealthService
                    // when Low Power Mode or Background App Refresh status changes.
                    // This ensures the health status bar updates in real time while
                    // the app is foregrounded, without requiring a scene phase transition.
                    healthService.startObserving { [self] in
                        healthService.evaluate(
                            isMonitoring: monitor.isMonitoring,
                            locationAuth: locationService.authorizationStatus,
                            backgroundRefresh: UIApplication.shared.backgroundRefreshStatus
                        )
                    }

                    // Evaluate initial health
                    healthService.evaluate(
                        isMonitoring: monitor.isMonitoring,
                        locationAuth: locationService.authorizationStatus,
                        backgroundRefresh: UIApplication.shared.backgroundRefreshStatus
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("com.cellguard.handleRefresh"))) { notification in
                    // Handle BGAppRefreshTask: run probe + schedule next (BKG-03)
                    guard let refreshTask = notification.object as? BGAppRefreshTask else { return }

                    refreshTask.expirationHandler = {
                        refreshTask.setTaskCompleted(success: false)
                    }

                    Task {
                        await monitor.runSingleProbe()
                        refreshTask.setTaskCompleted(success: true)
                        MonitoringHealthService.scheduleAppRefresh()
                    }
                }
        }
        .modelContainer(container)
    }
}
