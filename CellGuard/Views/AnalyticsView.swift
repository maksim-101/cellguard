import SwiftUI
import Charts
import SwiftData
import CoreLocation

/// Refined analytics for identifying patterns in connectivity drops (ANALYTICS-01, ANALYTICS-02).
struct AnalyticsView: View {
    let events: [ConnectivityEvent]

    @State private var selectedDimension: AnalyticsDimension = .radio
    @State private var resolvedNames: [String: String] = [:]

    enum AnalyticsDimension: String, CaseIterable, Identifiable {
        case radio = "Radio"
        case hour = "Hour"
        case interface = "Interface"
        var id: String { rawValue }
    }

    private var dropEvents: [ConnectivityEvent] {
        events.filter { isDropEvent($0) }
    }

    // MARK: - Key Drivers (Actionable Insights)

    private var insightFacts: [(icon: String, text: String, value: String)] {
        guard !dropEvents.isEmpty else { return [] }
        
        var facts: [(icon: String, text: String, value: String)] = []
        
        // 1. Silent Failure % (Dynamic calculation of % of total drops)
        let silentCount = dropEvents.filter { $0.eventType == .silentFailure }.count
        let silentPct = (Double(silentCount) / Double(dropEvents.count)) * 100
        facts.append(("waveform.path.badge.minus", "Silent Failures (of total drops)", String(format: "%.0f%%", silentPct)))
        
        // 2. NRNSA (5G) % (Dynamic calculation of % of total drops)
        let nrnsaCount = dropEvents.filter { $0.radioTechnology?.contains("NRNSA") == true }.count
        let nrnsaPct = (Double(nrnsaCount) / Double(dropEvents.count)) * 100
        if nrnsaPct > 0 {
            facts.append(("antenna.radiowaves.left.and.right", "Occurred on 5G (of total drops)", String(format: "%.0f%%", nrnsaPct)))
        }
        
        // 3. Peak Hour (Dynamic)
        let hours = dropEvents.map { Calendar.current.component(.hour, from: $0.timestamp) }
        if let peakHour = Dictionary(grouping: hours, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            facts.append(("clock", "Peak Drop Time", String(format: "%02d:00", peakHour)))
        }
        
        return facts
    }

    // MARK: - Trend Data (1D Bar Chart)

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
    }

    private var trendData: [TrendPoint] {
        var counts: [String: Int] = [:]
        
        for event in dropEvents {
            let label: String
            switch selectedDimension {
            case .hour:
                let hour = Calendar.current.component(.hour, from: event.timestamp)
                label = String(format: "%02d", hour)
            case .radio:
                label = event.radioTechnology?.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") ?? "Unknown"
            case .interface:
                // Map 'Other' to 'VPN' for actionable intelligence (POLISH-03)
                let type = event.interfaceType.encodingString.lowercased()
                label = (type == "other") ? "VPN" : type.capitalized
            }
            counts[label, default: 0] += 1
        }
        
        return counts.map { TrendPoint(label: $0.key, count: $0.value) }
            .sorted { $0.label < $1.label }
    }

    // MARK: - Ranked Locations (Enhanced)

    private struct LocationInsight {
        let cluster: String
        let count: Int
        let dominantTech: String?
    }

    private var rankedLocations: [LocationInsight] {
        let groups = Dictionary(grouping: dropEvents) { $0.locationCluster ?? "Unknown" }
        
        return groups.map { cluster, clusterEvents in
            // Determine dominant tech for this cluster
            let techs = clusterEvents.compactMap { $0.radioTechnology?.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") }
            let dominant = Dictionary(grouping: techs, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key
            
            return LocationInsight(cluster: cluster, count: clusterEvents.count, dominantTech: dominant)
        }
        .filter { $0.cluster != "Unknown" }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Body

    var body: some View {
        List {
            if dropEvents.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Data Available",
                        systemImage: "chart.pie",
                        description: Text("Analyze drops after they have been recorded with location data.")
                    )
                }
            } else {
                // Section 1: Actionable Insights
                Section("Key Drivers") {
                    ForEach(insightFacts, id: \.text) { fact in
                        HStack(spacing: 12) {
                            Image(systemName: fact.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text(fact.text)
                                .font(.subheadline)
                            Spacer()
                            Text(fact.value)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Section 2: Trends Chart (Replaces Heatmap)
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Dimension", selection: $selectedDimension) {
                            ForEach(AnalyticsDimension.allCases) { dim in
                                Text(dim.rawValue).tag(dim)
                            }
                        }
                        .pickerStyle(.segmented)

                        Chart(trendData) { point in
                            BarMark(
                                x: .value("Dimension", point.label),
                                y: .value("Drops", point.count)
                            )
                            .foregroundStyle(Color.red.gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 200)
                        .chartYAxis {
                            AxisMarks(preset: .automatic)
                        }
                        .chartXAxis {
                            if selectedDimension == .hour {
                                AxisMarks(values: ["00", "04", "08", "12", "16", "20", "23"]) { value in
                                    AxisGridLine()
                                    AxisValueLabel()
                                        .font(.system(size: 9))
                                }
                            } else {
                                AxisMarks(preset: .automatic) { _ in
                                    AxisGridLine()
                                    AxisValueLabel()
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Drop Trends")
                } footer: {
                    Text("Identify if drops are correlated with specific radio tech or times of day.")
                }

                // Section 3: Problem Areas
                Section("Ranked Locations") {
                    ForEach(rankedLocations, id: \.cluster) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: item.cluster))
                                    .font(.subheadline)
                                    .bold()
                                HStack(spacing: 4) {
                                    Text(item.cluster)
                                        .font(.system(size: 10, design: .monospaced))
                                    if let tech = item.dominantTech {
                                        Text("•")
                                        Text("Primarily \(tech)")
                                            .font(.caption2)
                                    }
                                }
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
        for item in rankedLocations {
            if resolvedNames[item.cluster] != nil { continue }
            
            let components = item.cluster.components(separatedBy: ", ")
            guard components.count == 2,
                  let lat = Double(components[0]),
                  let lon = Double(components[1]) else { continue }
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
                if let first = placemarks.first {
                    let name = [first.locality, first.subLocality].compactMap({ $0 }).joined(separator: ", ")
                    if !name.isEmpty {
                        resolvedNames[item.cluster] = name
                    }
                }
            } catch {
                // Ignore geocoding errors to keep UI responsive
            }
        }
    }
}
