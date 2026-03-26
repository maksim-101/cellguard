import SwiftUI
import Charts

/// Timeline visualization of drops over time (EXP-03).
///
/// Displays a scrollable 24-hour rolling window with 15-minute buckets.
/// Silent failures are red, overt drops are orange. The chart scrolls
/// horizontally when the time window contains data, with the most recent
/// time visible by default.
struct DropTimelineChart: View {
    let events: [ConnectivityEvent]

    /// Selected time window for the chart.
    @State private var selectedWindow: TimeWindow = .day

    enum TimeWindow: String, CaseIterable {
        case sixHours = "6h"
        case day = "24h"
        case week = "7d"

        var seconds: TimeInterval {
            switch self {
            case .sixHours: 6 * 3600
            case .day: 24 * 3600
            case .week: 7 * 24 * 3600
            }
        }

        /// Bucket size in seconds for this window.
        var bucketSeconds: TimeInterval {
            switch self {
            case .sixHours: 15 * 60      // 15-minute buckets
            case .day: 60 * 60           // 1-hour buckets
            case .week: 6 * 60 * 60      // 6-hour buckets
            }
        }

        /// Calendar component for bucket rounding.
        var bucketUnit: Calendar.Component {
            switch self {
            case .sixHours: .minute
            case .day: .hour
            case .week: .hour
            }
        }
    }

    private var dropEvents: [ConnectivityEvent] {
        let windowStart: Date
        if selectedWindow == .week {
            windowStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        } else {
            windowStart = Date().addingTimeInterval(-selectedWindow.seconds)
        }
        return events.filter { isDropEvent($0) && $0.timestamp >= windowStart }
    }

    /// Aggregated time bucket for chart rendering.
    private struct TimeBucket: Identifiable {
        let id = UUID()
        let bucketStart: Date
        let type: String
        let count: Int
    }

    /// Aggregates raw drop events into time buckets by type (Silent vs Overt).
    private var buckets: [TimeBucket] {
        let calendar = Calendar.current

        var grouped: [Date: [String: Int]] = [:]
        for event in dropEvents {
            let bucketDate: Date
            switch selectedWindow {
            case .sixHours:
                // Round down to nearest 15-minute boundary
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)
                let roundedMinute = (components.minute ?? 0) / 15 * 15
                var bucketComponents = components
                bucketComponents.minute = roundedMinute
                bucketComponents.second = 0
                bucketDate = calendar.date(from: bucketComponents) ?? event.timestamp
            case .day:
                // Round down to nearest hour
                bucketDate = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
            case .week:
                // Round down to nearest 6-hour block
                let components = calendar.dateComponents([.year, .month, .day, .hour], from: event.timestamp)
                let roundedHour = (components.hour ?? 0) / 6 * 6
                var bucketComponents = components
                bucketComponents.hour = roundedHour
                bucketComponents.minute = 0
                bucketComponents.second = 0
                bucketDate = calendar.date(from: bucketComponents) ?? event.timestamp
            }

            let type = event.eventType == .silentFailure ? "Silent" : "Overt"
            grouped[bucketDate, default: [:]][type, default: 0] += 1
        }

        var result: [TimeBucket] = []
        for (bucketStart, types) in grouped {
            for (type, count) in types {
                result.append(TimeBucket(bucketStart: bucketStart, type: type, count: count))
            }
        }
        return result.sorted { $0.bucketStart < $1.bucketStart }
    }

    /// The x-axis domain. For 7d view, aligns to calendar day boundaries
    /// (start of day 7 days ago through end of today) so weekday labels are clean.
    private var chartDomain: ClosedRange<Date> {
        let now = Date()
        let calendar = Calendar.current
        if selectedWindow == .week {
            let endOfToday = calendar.dateInterval(of: .day, for: now)!.end
            let startDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
            return startDay...endOfToday
        }
        let start = now.addingTimeInterval(-selectedWindow.seconds)
        let end = now.addingTimeInterval(selectedWindow.bucketSeconds)
        return start...end
    }

    /// Maximum Y value for consistent scaling.
    private var yMax: Int {
        let maxCount = buckets.map(\.count).max() ?? 1
        return max(maxCount + 1, 3) // At least 3 for readable scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Time window picker
            Picker("Window", selection: $selectedWindow) {
                ForEach(TimeWindow.allCases, id: \.self) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)

            if dropEvents.isEmpty {
                Text("No drops in \(selectedWindow.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.bucketStart, unit: selectedWindow.bucketUnit),
                        y: .value("Drops", bucket.count)
                    )
                    .foregroundStyle(by: .value("Type", bucket.type))
                }
                .chartForegroundStyleScale([
                    "Silent": .red,
                    "Overt": .orange
                ])
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: 0...yMax)
                .chartXAxis {
                    switch selectedWindow {
                    case .sixHours:
                        AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        }
                    case .day:
                        AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        }
                    case .week:
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartPlotStyle { plot in
                    plot.padding(.trailing, 4)
                }
                .frame(height: 150)
            }
        }
    }
}
