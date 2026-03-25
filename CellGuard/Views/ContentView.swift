import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var events: [ConnectivityEvent]

    var body: some View {
        NavigationStack {
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
            .navigationTitle("CellGuard")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Workaround: iOS 18+ @Query does not refresh after @ModelActor
                // background inserts. Force context to re-read from store when
                // app returns to foreground. See 01-RESEARCH.md Pitfall 1.
                modelContext.processPendingChanges()
            }
        }
    }
}
