import Foundation

/// Determines if a ConnectivityEvent represents a connectivity drop.
/// Used by dashboard counts (UI-01), summary report (EXP-02), and chart (EXP-03).
///
/// Classification:
/// - silentFailure (eventTypeRaw == 1) -> always a drop
/// - pathChange (eventTypeRaw == 0) with pathStatus unsatisfied (1) or requiresConnection (2) -> drop
/// - All other event types (probeSuccess, probeFailure, connectivityRestored, monitoringGap) -> NOT drops
func isDropEvent(_ event: ConnectivityEvent) -> Bool {
    switch event.eventType {
    case .silentFailure:
        return true
    case .pathChange:
        return event.pathStatus == .unsatisfied || event.pathStatus == .requiresConnection
    default:
        return false
    }
}
