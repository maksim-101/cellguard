import SwiftUI
import Charts

/// Timeline visualization of drops over time (EXP-03).
/// Uses BarMark with hourly temporal binning. Silent failures are red, overt drops are orange.
struct DropTimelineChart: View {
    let events: [ConnectivityEvent]

    private var dropEvents: [ConnectivityEvent] {
        events.filter { isDropEvent($0) }
    }

    var body: some View {
        if dropEvents.isEmpty {
            ContentUnavailableView(
                "No Drops Yet",
                systemImage: "chart.bar",
                description: Text("Drop timeline will appear when drops are detected.")
            )
            .frame(height: 200)
        } else {
            Chart(dropEvents) { event in
                BarMark(
                    x: .value("Time", event.timestamp, unit: .hour),
                    y: .value("Drops", 1)
                )
                .foregroundStyle(by: .value("Type",
                    event.eventType == .silentFailure ? "Silent" : "Overt"))
            }
            .chartForegroundStyleScale([
                "Silent": .red,
                "Overt": .orange
            ])
            .chartYAxisLabel("Drops")
            .frame(height: 200)
        }
    }
}
