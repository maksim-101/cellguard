import Foundation

/// Computed summary of all connectivity events for the evidence report (EXP-02).
struct SummaryReport {
    let totalDrops: Int
    let overtDrops: Int
    let silentDrops: Int
    let stallDrops: Int       // severeThroughput + dataStall + severeLatency — reachable but data/latency effectively dead
    let degradedCount: Int    // slow throughput / slow probes — NOT a drop
    let averageDurationSeconds: Double?
    let maxDurationSeconds: Double?
    let dropsPerDay: Double
    let dropRatio: Double?      // drops / cellular activity (REPORT-02)
    let degradedRatio: Double?  // degraded / cellular activity
    let monitoringDays: Int
    let totalEvents: Int
    let radioDistribution: [(radio: String, count: Int)]
    let locationClusters: Int

    /// Generates a summary report from a complete event array.
    /// The drop/failure breakdown comes from `HealthScore.failureCounts` so the report stays
    /// consistent with the home screen's Cellular Health counts (cellular-only, Wi-Fi excluded).
    static func generate(from events: [ConnectivityEvent]) -> SummaryReport {
        let fc = HealthScore.failureCounts(events: events, since: nil)

        // Drop events for the descriptive stats (duration / radio / location). Same population as
        // fc.drops: silent & stall are inherently cellular, and isDropEvent gates pathChange on cellular.
        let drops = events.filter { isDropEvent($0) }

        // Duration stats from drops that have dropDurationSeconds
        let durations = drops.compactMap(\.dropDurationSeconds)
        let avgDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max()

        // Correct monitoringDays (REPORT-01): count distinct calendar days with data.
        let calendar = Calendar.current
        let uniqueDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        let daySpan = max(uniqueDays.count, 1)

        let dropsPerDay = Double(fc.drops) / Double(daySpan)

        // Drop / degraded ratios (REPORT-02): over cellular activity = cellular probe outcomes plus
        // overt path drops (which aren't probes). Drops and degraded are both subsets of this, so the
        // ratios stay in 0–100%. Uses HealthScore's cellular discrimination (VPN-tolerant), unlike the
        // old `interfaceType == .cellular` denominator which read empty under an always-on VPN.
        let cellularActivity = fc.probes + fc.overt
        let dropRatio = cellularActivity > 0 ? Double(fc.drops) / Double(cellularActivity) : nil
        let degradedRatio = cellularActivity > 0 ? Double(fc.degraded) / Double(cellularActivity) : nil

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
            totalDrops: fc.drops,
            overtDrops: fc.overt,
            silentDrops: fc.silent,
            stallDrops: fc.stall,
            degradedCount: fc.degraded,
            averageDurationSeconds: avgDuration,
            maxDurationSeconds: maxDuration,
            dropsPerDay: dropsPerDay,
            dropRatio: dropRatio,
            degradedRatio: degradedRatio,
            monitoringDays: daySpan,
            totalEvents: events.count,
            radioDistribution: radioDistribution,
            locationClusters: locationClusters
        )
    }
}
