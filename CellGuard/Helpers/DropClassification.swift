import Foundation

/// Determines if a ConnectivityEvent represents a connectivity drop.
/// Used by dashboard counts (UI-01), summary report (EXP-02), and chart (EXP-03).
///
/// Classification:
/// - silentFailure (eventTypeRaw == 1) -> always a drop (unreachable — nothing got through)
/// - severeThroughput (eventTypeRaw == 8) -> always a drop (reachable, but bulk data effectively
///   unusable). Distinct failure mode from silentFailure; slowThroughput is degraded-but-functional
///   and is NOT a drop.
/// - pathChange (eventTypeRaw == 0) with pathStatus unsatisfied (1) or requiresConnection (2)
///   -> drop ONLY when it was a cellular loss (interfaceType cellular, or legacy .unknown).
///   Wi-Fi handover gaps record interfaceType .wifi and are excluded so they don't inflate
///   the cellular-drop count.
/// - dataStall (eventTypeRaw == 11) -> always a drop (a sustained-transfer freeze long enough
///   to break a real-time call — reachable but unusable for VoIP/video).
/// - severeLatency (eventTypeRaw == 12) -> always a drop (reachable, but a >5s probe over a radio
///   that measured healthy throughput within the freshness window — i.e. the modem stalled on a
///   demonstrably capable link, not weak coverage).
/// - All other event types (probeSuccess, probeFailure, slowThroughput, connectivityRestored,
///   monitoringGap, radioTechChange, userIncident) -> NOT drops. probeSuccess stays in this list:
///   a severe-latency event is no longer typed probeSuccess.
func isDropEvent(_ event: ConnectivityEvent) -> Bool {
    switch event.eventType {
    case .silentFailure:
        return true
    case .severeThroughput:
        return true
    case .dataStall:
        return true
    case .severeLatency:
        return true
    case .pathChange:
        guard event.pathStatus == .unsatisfied || event.pathStatus == .requiresConnection else { return false }
        // Only count cellular drops; exclude Wi-Fi handover gaps. New overt-drop events record the
        // dropped interface (previousInterfaceType); legacy events recorded .unknown for any unsatisfied
        // path, so treat .unknown as countable to preserve historical drop counts.
        return event.interfaceType == .cellular || event.interfaceType == .unknown
    default:
        return false
    }
}
