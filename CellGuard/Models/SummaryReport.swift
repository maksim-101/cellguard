import Foundation

/// Computed summary of all connectivity events for the evidence report (EXP-02).
struct SummaryReport {
    let totalDrops: Int
    let overtDrops: Int
    let silentDrops: Int
    let averageDurationSeconds: Double?
    let maxDurationSeconds: Double?
    let dropsPerDay: Double
    let monitoringDays: Int
    let totalEvents: Int
    let radioDistribution: [(radio: String, count: Int)]
    let locationClusters: Int

    /// Generates a summary report from a complete event array.
    /// Uses isDropEvent() for consistent drop classification across all UI.
    static func generate(from events: [ConnectivityEvent]) -> SummaryReport {
        let drops = events.filter { isDropEvent($0) }
        let silent = drops.filter { $0.eventType == .silentFailure }
        let overt = drops.filter { $0.eventType != .silentFailure }

        // Duration stats from drops that have dropDurationSeconds
        let durations = drops.compactMap(\.dropDurationSeconds)
        let avgDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max()

        // Days spanned for drops-per-day calculation
        let timestamps = events.map(\.timestamp).sorted()
        let daySpan: Int
        if let first = timestamps.first, let last = timestamps.last {
            daySpan = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1)
        } else {
            daySpan = 1
        }
        let dropsPerDay = Double(drops.count) / Double(daySpan)

        // Radio technology distribution (strip CTRadioAccessTechnology prefix)
        let radioGroups = Dictionary(grouping: drops) {
            $0.radioTechnology?
                .replacingOccurrences(of: "CTRadioAccessTechnology", with: "") ?? "Unknown"
        }
        let radioDistribution = radioGroups
            .map { (radio: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        // Location clusters: count distinct ~1km grid cells (round to 2 decimal places)
        let locationClusters = countLocationClusters(drops)

        return SummaryReport(
            totalDrops: drops.count,
            overtDrops: overt.count,
            silentDrops: silent.count,
            averageDurationSeconds: avgDuration,
            maxDurationSeconds: maxDuration,
            dropsPerDay: dropsPerDay,
            monitoringDays: daySpan,
            totalEvents: events.count,
            radioDistribution: radioDistribution,
            locationClusters: locationClusters
        )
    }

    /// Counts distinct ~1km grid cells containing drop events.
    /// Rounds lat/lon to 2 decimal places (~1.1km at equator).
    private static func countLocationClusters(_ events: [ConnectivityEvent]) -> Int {
        var cells = Set<String>()
        for event in events {
            if let lat = event.latitude, let lon = event.longitude {
                let key = "\(String(format: "%.2f", lat)),\(String(format: "%.2f", lon))"
                cells.insert(key)
            }
        }
        return cells.count
    }
}
