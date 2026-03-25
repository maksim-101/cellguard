import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(LocationService.self) private var locationService
    @Environment(MonitoringHealthService.self) private var healthService
    @Environment(ProvisioningProfileService.self) private var profileService

    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var events: [ConnectivityEvent]

    @State private var showHealthSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Health status bar (tappable, opens detail sheet)
                Button {
                    showHealthSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(healthDotColor)
                            .frame(width: 8, height: 8)
                        Text(healthLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let radio = monitor.currentRadioTechnology {
                            Text(radio.replacingOccurrences(of: "CTRadioAccessTechnology", with: ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Monitoring \(healthAccessibilityLabel), tap for details")
                .padding(.bottom, 8)

                // Event list or empty state
                Group {
                    if events.isEmpty {
                        ContentUnavailableView(
                            "No Events",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("CellGuard is ready. Events will appear here when monitoring starts.")
                        )
                    } else {
                        List(events) { event in
                            if event.eventType == .monitoringGap {
                                gapEventRow(event)
                            } else {
                                standardEventRow(event)
                            }
                        }
                    }
                }
            }
            .navigationTitle("CellGuard")
        }
        .sheet(isPresented: $showHealthSheet) {
            HealthDetailSheet()
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

    // MARK: - Health Status Bar Helpers

    private var healthDotColor: Color {
        switch healthService.health {
        case .active: .green
        case .degraded: .orange
        case .paused: .red
        }
    }

    private var healthLabel: String {
        switch healthService.health {
        case .active: "Monitoring Active"
        case .degraded: "Monitoring Degraded"
        case .paused: "Monitoring Paused"
        }
    }

    private var healthAccessibilityLabel: String {
        switch healthService.health {
        case .active: "active"
        case .degraded: "degraded"
        case .paused: "paused"
        }
    }

    // MARK: - Event Row Views

    @ViewBuilder
    private func standardEventRow(_ event: ConnectivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.eventType.displayName)
                .font(.headline)
            Text(event.timestamp, format: .dateTime)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func gapEventRow(_ event: ConnectivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.eventType.displayName)
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                Text("Monitoring was suspended")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let gapDuration = event.dropDurationSeconds {
                let endTime = event.timestamp.addingTimeInterval(gapDuration)
                Text("\(event.timestamp, format: .dateTime.hour().minute()) - \(endTime, format: .dateTime.hour().minute()) (\(Int(gapDuration / 60)) min)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
