import SwiftUI
import Charts
import SwiftData

/// Detailed location-based analytics for drop events (ANALYTICS-01, ANALYTICS-02).
struct AnalyticsView: View {
    let events: [ConnectivityEvent]

    @State private var selectedDimension: AnalyticsDimension = .hour

    enum AnalyticsDimension: String, CaseIterable, Identifiable {
        case hour = "Hour"
        case radio = "Radio"
        case interface = "Interface"
        var id: String { rawValue }
    }

    private var dropEvents: [ConnectivityEvent] {
        events.filter { isDropEvent($0) }
    }

    /// Aggregates drops by [Location: [Dimension: Count]]
    private var heatmapData: [HeatmapPoint] {
        var counts: [String: [String: Int]] = [:]
        
        for event in dropEvents {
            guard let cluster = event.locationCluster else { continue }
            let dimensionValue: String
            
            switch selectedDimension {
            case .hour:
                let hour = Calendar.current.component(.hour, from: event.timestamp)
                dimensionValue = String(format: "%02d", hour)
            case .radio:
                dimensionValue = event.radioTechnology?.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") ?? "Unknown"
            case .interface:
                dimensionValue = event.interfaceType.encodingString
            }
            
            counts[cluster, default: [:]][dimensionValue, default: 0] += 1
        }
        
        var points: [HeatmapPoint] = []
        for (cluster, dims) in counts {
            for (dim, count) in dims {
                points.append(HeatmapPoint(location: cluster, dimension: dim, count: count))
            }
        }
        return points
    }

    private var rankedLocations: [(location: String, count: Int)] {
        let groups = Dictionary(grouping: dropEvents.compactMap(\.locationCluster)) { $0 }
        return groups.map { (location: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List {
            Section {
                Picker("Dimension", selection: $selectedDimension) {
                    ForEach(AnalyticsDimension.allCases) { dim in
                        Text(dim.rawValue).tag(dim)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 8)
            } header: {
                Text("Heatmap X-Axis")
            }

            Section("Drop Heatmap") {
                if heatmapData.isEmpty {
                    ContentUnavailableView(
                        "No Location Data",
                        systemImage: "map",
                        description: Text("Drop events must have location data to appear here.")
                    )
                    .frame(height: 200)
                } else {
                    Chart(heatmapData) { point in
                        RectangleMark(
                            x: .value("Dimension", point.dimension),
                            y: .value("Location", point.location),
                            width: .ratio(1),
                            height: .ratio(1)
                        )
                        .foregroundStyle(by: .value("Drops", point.count))
                    }
                    .chartForegroundStyleScale(
                        range: Gradient(colors: [.orange.opacity(0.2), .red])
                    )
                    .chartYAxis {
                        AxisMarks(preset: .automatic) { _ in
                            AxisValueLabel()
                                .font(.system(size: 8, design: .monospaced))
                        }
                    }
                    .frame(height: 300)
                    .padding(.vertical)
                }
            }

            Section("Ranked Locations") {
                if rankedLocations.isEmpty {
                    Text("No location data available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rankedLocations, id: \.location) { item in
                        HStack {
                            Text(item.location)
                                .font(.system(.subheadline, design: .monospaced))
                            Spacer()
                            Text("\(item.count)")
                                .bold()
                                .foregroundStyle(item.count > 5 ? .red : .primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Location Analytics")
    }

    private struct HeatmapPoint: Identifiable {
        let id = UUID()
        let location: String
        let dimension: String
        let count: Int
    }
}
