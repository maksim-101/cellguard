import SwiftUI
import SwiftData

/// Root view that provides NavigationStack and manages app-level lifecycle.
///
/// All UI content has been decomposed into DashboardView, EventListView,
/// and EventDetailView. ContentView retains only the NavigationStack shell
/// and the scenePhase lifecycle handler (processPendingChanges workaround,
/// probe timer management, health re-evaluation, BGAppRefreshTask scheduling).
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(LocationService.self) private var locationService
    @Environment(MonitoringHealthService.self) private var healthService
    @Environment(ProvisioningProfileService.self) private var profileService

    var body: some View {
        NavigationStack {
            DashboardView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Workaround: iOS 18+ @Query does not refresh after @ModelActor
                // background inserts. Force context to re-read from store when
                // app returns to foreground. See 01-RESEARCH.md Pitfall 1.
                modelContext.processPendingChanges()

                // Resume probe timer in foreground (only if monitoring is active)
                if monitor.isMonitoring {
                    monitor.startProbeTimer()
                }

                // Re-evaluate health on foreground return (catches changes that happened
                // while backgrounded, complementing the real-time onConditionChanged callback)
                healthService.evaluate(
                    isMonitoring: monitor.isMonitoring,
                    locationAuth: locationService.authorizationStatus,
                    backgroundRefresh: UIApplication.shared.backgroundRefreshStatus
                )
            } else if newPhase == .background {
                // Timer suspended by iOS in background
                monitor.stopProbeTimer()

                // Schedule BGAppRefreshTask on background entry (BKG-03)
                MonitoringHealthService.scheduleAppRefresh()
            }
        }
    }
}
