import SwiftUI
import Charts
import SwiftData
import CoreLocation

/// Detailed location-based analytics for drop events (ANALYTICS-01, ANALYTICS-02).
struct AnalyticsView: View {
    let events: [ConnectivityEvent]

    @State private var selectedDimension: AnalyticsDimension = .hour
    @State private var resolvedNames: [String: String] = [:]

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
                Text("Heatmap Axis")
            } footer: {
                Text("Switching dimensions helps identify if drops happen at specific times, on specific radio tech (like NRNSA vs LTE), or interface types.")
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
                            y: .value("Location", displayName(for: point.location)),
                            width: .ratio(0.9),
                            height: .ratio(0.9)
                        )
                        .foregroundStyle(by: .value("Drops", point.count))
                    }
                    .chartForegroundStyleScale(
                        range: Gradient(colors: [.orange.opacity(0.3), .red])
                    )
                    .chartYAxis {
                        AxisMarks(preset: .automatic) { _ in
                            AxisValueLabel()
                                .font(.system(size: 9))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(preset: .automatic) { _ in
                            AxisValueLabel()
                                .font(.system(size: 9))
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: item.location))
                                    .font(.subheadline)
                                    .bold()
                                Text(item.location)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
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
        .task {
            await resolveNames()
        }
    }

    private func displayName(for cluster: String) -> String {
        resolvedNames[cluster] ?? cluster
    }

    private func resolveNames() async {
        let geocoder = CLGeocoder()
        for cluster in rankedLocations.map({ $0.location }) {
            if resolvedNames[cluster] != nil { continue }
            
            let components = cluster.components(separatedBy: ", ")
            guard components.count == 2,
                  let lat = Double(components[0]),
                  let lon = Double(components[1]) else { continue }
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
                if let first = placemarks.first {
                    let name = [first.locality, first.subLocality].compactMap({ $0 }).joined(separator: ", ")
                    if !name.isEmpty {
                        resolvedNames[cluster] = name
                    }
                }
            } catch {
                // Ignore errors for individual clusters to keep moving
            }
        }
    }

    private struct HeatmapPoint: Identifiable {
        let id = UUID()
        let location: String
        let dimension: String
        let count: Int
    }
}
