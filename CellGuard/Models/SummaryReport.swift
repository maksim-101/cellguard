import Foundation

/// Computed summary of all connectivity events for the evidence report (EXP-02).
struct SummaryReport {
    let totalDrops: Int
    let overtDrops: Int
    let silentDrops: Int
    let averageDurationSeconds: Double?
    let maxDurationSeconds: Double?
    let dropsPerDay: Double
    let dropRatio: Double? // New (REPORT-02)
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

        // 1. Correct monitoringDays (REPORT-01): count distinct calendar days with data.
        // This ignores certification gaps and periods where the app was not running.
        let calendar = Calendar.current
        let uniqueDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        let daySpan = max(uniqueDays.count, 1)

        let dropsPerDay = Double(drops.count) / Double(daySpan)

        // 2. Drop Ratio (REPORT-02): drops / cellular events (the meaningful denominator).
        let cellularEvents = events.filter { $0.interfaceType == .cellular }.count
        let dropRatio = (cellularEvents > 0) ? Double(drops.count) / Double(cellularEvents) : nil

        // Radio technology distribution (strip CTRadioAccessTechnology prefix)
        let radioGroups = Dictionary(grouping: drops) {
            $0.radioTechnology?
                .replacingOccurrences(of: "CTRadioAccessTechnology", with: "") ?? "Unknown"
        }
        let radioDistribution = radioGroups
            .map { (radio: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        // Location clusters: count distinct ~1km grid cells
        let locationClusters = Set(drops.compactMap(\.locationCluster)).count

        return SummaryReport(
            totalDrops: drops.count,
            overtDrops: overt.count,
            silentDrops: silent.count,
            averageDurationSeconds: avgDuration,
            maxDurationSeconds: maxDuration,
            dropsPerDay: dropsPerDay,
            dropRatio: dropRatio,
            monitoringDays: daySpan,
            totalEvents: events.count,
            radioDistribution: radioDistribution,
            locationClusters: locationClusters
        )
    }
}
