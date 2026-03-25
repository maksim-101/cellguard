import SwiftUI
import Charts

/// Timeline visualization of drops over time (EXP-03).
/// Aggregates drop events into hourly buckets and renders discrete bars.
/// Silent failures are red, overt drops are orange.
struct DropTimelineChart: View {
    let events: [ConnectivityEvent]

    private var dropEvents: [ConnectivityEvent] {
        events.filter { isDropEvent($0) }
    }

    /// Aggregated time bucket for chart rendering.
    /// Groups drop events by hour and type to produce discrete, non-overlapping bars.
    private struct TimeBucket: Identifiable {
        let id = UUID()
        let hour: Date
        let type: String
        let count: Int
    }

    /// Aggregates raw drop events into 15-minute buckets by type (Silent vs Overt).
    /// Uses 15-minute intervals instead of hourly to produce narrower, more readable bars
    /// even when there's only a small window of data.
    private var buckets: [TimeBucket] {
        let calendar = Calendar.current

        // Group events by (15-min interval, type)
        var grouped: [Date: [String: Int]] = [:]
        for event in dropEvents {
            // Round down to nearest 15-minute boundary
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)
            let roundedMinute = (components.minute ?? 0) / 15 * 15
            var bucketComponents = components
            bucketComponents.minute = roundedMinute
            bucketComponents.second = 0
            let bucketDate = calendar.date(from: bucketComponents) ?? event.timestamp

            let type = event.eventType == .silentFailure ? "Silent" : "Overt"
            grouped[bucketDate, default: [:]][type, default: 0] += 1
        }

        // Flatten into TimeBucket array
        var result: [TimeBucket] = []
        for (hour, types) in grouped {
            for (type, count) in types {
                result.append(TimeBucket(hour: hour, type: type, count: count))
            }
        }
        return result.sorted { $0.hour < $1.hour }
    }

    /// The x-axis domain — always show at least 6 hours so bars remain narrow.
    private var chartDomain: ClosedRange<Date> {
        let now = Date()
        let sixHoursAgo = now.addingTimeInterval(-6 * 3600)

        if let earliest = dropEvents.map(\.timestamp).min() {
            let start = min(earliest.addingTimeInterval(-900), sixHoursAgo) // 15-min padding
            return start...now.addingTimeInterval(900)
        }
        return sixHoursAgo...now
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
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.hour, unit: .minute),
                    y: .value("Drops", bucket.count),
                    width: 8
                )
                .foregroundStyle(by: .value("Type", bucket.type))
            }
            .chartForegroundStyleScale([
                "Silent": .red,
                "Overt": .orange
            ])
            .chartXScale(domain: chartDomain)
            .chartYAxisLabel("Drops")
            .frame(height: 200)
        }
    }
}
