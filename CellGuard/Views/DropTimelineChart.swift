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

    /// Whether silent-failure bars are visible in the chart. Tapping the "Silent"
    /// legend chip toggles this. Persists via @AppStorage (D-07). Default true (D-06).
    @AppStorage("chartShowSilent") private var chartShowSilent: Bool = true

    /// Whether overt path-change drop bars are visible. Tapping the "Overt" chip
    /// toggles this. Persists via @AppStorage (D-07). Default true (D-06).
    @AppStorage("chartShowOvert") private var chartShowOvert: Bool = true

    /// Drives the (i) info popover anchored to the info Button (D-02).
    @State private var showInfoPopover: Bool = false

    /// Single source of truth for the chart's drop-series discriminator (MN-02).
    /// rawValue strings are the SAME literals previously scattered across 5+ sites.
    /// Identifiable + CaseIterable so future iteration over series is trivial.
    private enum DropSeries: String, CaseIterable, Identifiable, Plottable {
        case silent = "Silent"
        case overt = "Overt"
        var id: String { rawValue }
    }

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
        let type: DropSeries
        let count: Int
    }

    /// Aggregates raw drop events into time buckets by type (Silent vs Overt).
    private var buckets: [TimeBucket] {
        let calendar = Calendar.current

        var grouped: [Date: [DropSeries: Int]] = [:]
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

            let type: DropSeries = (event.eventType == .silentFailure) ? .silent : .overt
            grouped[bucketDate, default: [:]][type, default: 0] += 1
        }

        var result: [TimeBucket] = []
        for (bucketStart, types) in grouped {
            for (type, count) in types {
                result.append(TimeBucket(bucketStart: bucketStart, type: type, count: count))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.bucketStart != rhs.bucketStart { return lhs.bucketStart < rhs.bucketStart }
            return lhs.type.rawValue < rhs.type.rawValue   // deterministic Silent-before-Overt
        }
    }

    /// Same shape as `buckets`, but filtered by the @AppStorage chip flags.
    /// Toggled-off series are entirely removed from the chart input — D-05 hides
    /// (does not dim) so the chart literally answers CHART-02 "only silent
    /// failures remain visible" when overt is off.
    private var visibleBuckets: [TimeBucket] {
        buckets.filter { bucket in
            switch bucket.type {
            case .silent: return chartShowSilent
            case .overt:  return chartShowOvert
            }
        }
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
    /// Uses stacked totals per time slot (sum of all types sharing the same
    /// bucketStart) because BarMark with foregroundStyle(by:) stacks bars.
    private var yMax: Int {
        // Group by bucketStart and sum counts across types (Silent + Overt)
        // to match the stacked bar height Swift Charts actually renders.
        var stackedTotals: [Date: Int] = [:]
        for bucket in buckets {
            stackedTotals[bucket.bucketStart, default: 0] += bucket.count
        }
        let maxStacked = stackedTotals.values.max() ?? 1
        return max(maxStacked + 1, 3) // At least 3 for readable scale
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

            // Inline legend chips + (i) info button (D-01, D-02, D-04).
            // The chips ARE the filter — single discoverable surface.
            legendBar

            if dropEvents.isEmpty {
                Text("No drops in \(selectedWindow.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else if !chartShowSilent && !chartShowOvert {
                // D-07 edge case: both series toggled off. Show a hint instead
                // of an empty plot so the user understands why the chart is blank.
                Text("No series visible — tap a chip to enable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else {
                Chart(visibleBuckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.bucketStart, unit: selectedWindow.bucketUnit),
                        y: .value("Drops", bucket.count)
                    )
                    .foregroundStyle(by: .value("Type", bucket.type))
                }
                .chartForegroundStyleScale([
                    DropSeries.silent.rawValue: Color.red,
                    DropSeries.overt.rawValue: Color.orange
                ])
                // REQUIRED (D-04): suppress Swift Charts' implicit auto-legend that
                // would otherwise render below the plot whenever
                // chartForegroundStyleScale is set. The custom legendBar chips above
                // ARE the legend — shipping both creates duplicated UI and contradicts
                // the "single discoverable surface" decision.
                .chartLegend(.hidden)
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: 0...yMax)
                .chartXAxis {
                    switch selectedWindow {
                    case .sixHours:
                        AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                                .font(.caption2)
                        }
                    case .day:
                        AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        }
                    case .week:
                        AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartPlotStyle { plot in
                    plot.padding(.trailing, 4)
                }
                .padding(.top, 8) // Fix Y-axis clipping at the top
                .frame(height: 150)
                .clipped()
            }
        }
    }

    // MARK: - Legend & Info Popover (D-01, D-02, D-04)

    /// Compact inline legend that doubles as a series filter (D-01, D-04).
    /// Two color-coded chips + an (i) info Button. Tapping a chip toggles its
    /// @AppStorage flag; tapping (i) opens the popover with plain-English
    /// definitions and the "Why this matters for the Apple report" line.
    private var legendBar: some View {
        HStack(spacing: 12) {
            legendChip(label: DropSeries.silent.rawValue, color: .red, isOn: chartShowSilent) {
                chartShowSilent.toggle()
            }
            legendChip(label: DropSeries.overt.rawValue, color: .orange, isOn: chartShowOvert) {
                chartShowOvert.toggle()
            }
            Button {
                showInfoPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
                ScrollView {
                    infoPopoverContent
                        .padding(24)
                }
                .frame(width: 320, height: 360)
                .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
        }
    }

    /// One legend chip — a tappable Button styled as a Capsule with a color swatch.
    /// "Off" treatment: opacity 0.4 when isOn==false (HIG-aligned de-emphasis).
    /// The chip remains tappable in the off state so the user can re-enable.
    private func legendChip(label: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
            .opacity(isOn ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) drops")
        .accessibilityValue(isOn ? "Visible" : "Hidden")
        .accessibilityHint("Double-tap to toggle \(label.lowercased()) drops")
    }

    /// Popover content (D-02). Plain-English Silent/Overt definitions plus a
    /// rationale line tying the distinction back to the Apple Feedback Assistant
    /// report (the project's core value — see PROJECT.md core_value).
    private var infoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drop Types")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DropSeries.silent.rawValue).font(.subheadline).bold()
                        Text("The modem reports it is connected, but the network probe failed — the \u{201C}attached but unreachable\u{201D} bug.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(.orange).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DropSeries.overt.rawValue).font(.subheadline).bold()
                        Text("NWPathMonitor reported the connection went down — the system itself acknowledged the drop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            Text("Why this matters")
                .font(.subheadline).bold()
            Text("Silent failures are the core evidence for the Apple Feedback Assistant report — they prove a modem-side fault that iOS itself does not report.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
