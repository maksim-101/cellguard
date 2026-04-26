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

    @State private var filter: EventFilter = .all

    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drops = "Drops"
        case silent = "Silent"
        case overt = "Overt"
        var id: String { rawValue }
    }

    private var filteredEvents: [ConnectivityEvent] {
        switch filter {
        case .all:
            return events
        case .drops:
            return events.filter { isDropEvent($0) }
        case .silent:
            return events.filter { $0.eventType == .silentFailure }
        case .overt:
            return events.filter { isDropEvent($0) && $0.eventType != .silentFailure }
        }
    }

    var body: some View {
        Group {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "No Events" : "No Matching Events",
                    systemImage: filter == .all ? "antenna.radiowaves.left.and.right.slash" : "line.3.horizontal.decrease.circle",
                    description: Text(filter == .all ? "Events will appear here when monitoring starts." : "Try changing the filter to see more events.")
                )
            } else {
                List(filteredEvents) { event in
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(EventFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filter.rawValue)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
        }
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
