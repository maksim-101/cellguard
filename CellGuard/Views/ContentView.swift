import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectivityMonitor.self) private var monitor
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var events: [ConnectivityEvent]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Monitoring status bar
                HStack {
                    Circle()
                        .fill(monitor.isMonitoring ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(monitor.isMonitoring ? "Monitoring Active" : "Monitoring Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let radio = monitor.currentRadioTechnology {
                        Text(radio.replacingOccurrences(of: "CTRadioAccessTechnology", with: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.eventType.displayName)
                                    .font(.headline)
                                Text(event.timestamp, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("CellGuard")
        }
        .onAppear {
            monitor.startMonitoring()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Workaround: iOS 18+ @Query does not refresh after @ModelActor
                // background inserts. Force context to re-read from store when
                // app returns to foreground. See 01-RESEARCH.md Pitfall 1.
                modelContext.processPendingChanges()

                // Resume probe timer in foreground
                monitor.startProbeTimer()
            } else if newPhase == .background {
                // Timer suspended by iOS in background. Phase 3 adds wake-then-probe
                // via significant location changes.
                monitor.stopProbeTimer()
            }
        }
    }
}
