import SwiftUI
import SwiftData

/// Scrollable reverse-chronological event log (UI-02).
///
/// Each event is a NavigationLink to EventDetailView for full metadata.
/// Monitoring gap events render with a distinct layout showing the gap
/// time range and duration. Drop events show colored severity indicators.
struct EventListView: View {
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var events: [ConnectivityEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Events will appear here when monitoring starts.")
                )
            } else {
                List(events) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        if event.eventType == .monitoringGap {
                            gapEventRow(event)
                        } else {
                            standardEventRow(event)
                        }
                    }
                }
            }
        }
        .navigationTitle("Events")
    }

    // MARK: - Event Row Views

    @ViewBuilder
    private func standardEventRow(_ event: ConnectivityEvent) -> some View {
        HStack(spacing: 8) {
            // Drop severity indicator
            if isDropEvent(event) {
                Circle()
                    .fill(event.eventType == .silentFailure ? Color.red : Color.orange)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventType.displayName)
                    .font(.headline)
                Text(event.timestamp, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
