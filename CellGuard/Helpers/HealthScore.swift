import SwiftUI
import Foundation

/// Pure computation helper for the Cellular Health score system (Option H).
///
/// All methods are static and synchronous — no async, no SwiftData, no I/O.
/// Single source of truth for every score, count, and verdict rendered on the home screen.
enum HealthScore {

    // MARK: - Tunable Constants

    /// Probes with latency above this threshold are counted as degraded even when reachability succeeds.
    static let slowLatencyThresholdMs: Double = 3000

    /// Minimum cellular probes required before a score is meaningful.
    /// Below this the window is too small to grade reliably.
    static let minCellularProbesForScore = 10

    // MARK: - Private Helpers

    /// EventTypes that carry an active probe outcome from the cellular link.
    /// Non-outcome types (pathChange, connectivityRestored, monitoringGap, vpnStateChange)
    /// are excluded — they do not reflect a reachability probe result.
    private static let probeOutcomeTypes: Set<EventType> = [
        .probeSuccess, .probeFailure, .silentFailure, .slowThroughput, .severeThroughput, .dataStall
    ]

    /// Applies the time window filter. Returns the full array when `since` is nil.
    private static func windowed(_ events: [ConnectivityEvent], since: Date?) -> [ConnectivityEvent] {
        guard let since else { return events }
        return events.filter { $0.timestamp >= since }
    }

    /// Whether an event's probe ran over the cellular data path (Wi-Fi excluded).
    ///
    /// Two complementary signals, OR'd so the score works on BOTH legacy and new data:
    /// - `pathUsesCellular` — the precise per-probe NWPath signal (only set on events captured
    ///   after that field shipped; survives a VPN tunnel).
    /// - A radio-based fallback for legacy events that predate `pathUsesCellular`: the cellular
    ///   modem is attached (`radioTechnology != nil`, e.g. NRNSA/LTE) AND the probe was NOT on
    ///   Wi-Fi. The Wi-Fi exclusion is essential — the modem stays attached/reports a radio tech
    ///   even while traffic flows over Wi-Fi, so radioTechnology alone would count clean Wi-Fi
    ///   probes as cellular and inflate the score. `wifiSSID == nil && interfaceType != .wifi`
    ///   rules out both direct Wi-Fi and VPN-over-Wi-Fi.
    static func isCellular(_ e: ConnectivityEvent) -> Bool {
        if e.pathUsesCellular { return true }
        return e.radioTechnology != nil && e.wifiSSID == nil && e.interfaceType != .wifi
    }

    // MARK: - Score

    /// Computes a 0–100 health score from cellular probe outcomes in the given window.
    ///
    /// Returns nil when fewer than `minCellularProbesForScore` cellular probes are present
    /// (not enough evidence for a reliable grade). Cellular-vs-Wi-Fi is decided by `isCellular`.
    static func score(events: [ConnectivityEvent], since: Date?) -> Double? {
        let w = windowed(events, since: since)
        let probes = w.filter { probeOutcomeTypes.contains($0.eventType) && isCellular($0) }
        guard probes.count >= minCellularProbesForScore else { return nil }
        // Clean is a strict subset of cellular probes: probeSuccess with latency within threshold.
        // Always filter the probe set — never raw events — so the denominator is consistent.
        let clean = probes.filter {
            $0.eventType == .probeSuccess && ($0.probeLatencyMs ?? 0) <= slowLatencyThresholdMs
        }
        return 100 * Double(clean.count) / Double(probes.count)
    }

    // MARK: - Band

    /// Maps a numeric score to a human label and a tint color.
    static func band(for score: Double) -> (label: String, color: Color) {
        switch score {
        case 80...:   return ("Good", .green)
        case 60..<80: return ("Fair", .yellow)
        case 40..<60: return ("Poor", .orange)
        case 20..<40: return ("Bad", Color(red: 1, green: 0.42, blue: 0.13))
        default:      return ("Critical", .red)
        }
    }

    // MARK: - Verdict

    /// Compares last-24h health against overall health to produce a trend verdict.
    ///
    /// Returns nil when either score is nil (not enough data for that window).
    ///
    /// Cascade ordering: each branch is an open lower bound evaluated top-down, making ranges
    /// mutually exclusive without listing both ends. Writing literal ranges (e.g. `4.0..<10.0`)
    /// would leave a gap between −4 and −3 where no branch fires; the cascade closes that gap.
    static func verdict(last24h: Double?, overall: Double?) -> (text: String, symbol: String, color: Color)? {
        guard let last24h, let overall else { return nil }
        let delta = last24h - overall
        if delta >= 10  { return ("Much better than usual", "arrow.up.to.line", .green) }
        if delta >= 4   { return ("Better than usual", "arrow.up", .green) }
        if delta >= -3  { return ("Typical", "equal", .secondary) }
        if delta > -10  { return ("Worse than usual", "arrow.down", .orange) }
        return ("Much worse than usual", "arrow.down.to.line", .red)
    }

    // MARK: - Failure Counts

    struct FailureCounts {
        let silent: Int
        let overt: Int
        let stall: Int
        let degraded: Int
        let drops: Int
        let probes: Int
    }

    /// Breaks down cellular events in the window into failure-mode counts.
    ///
    /// - `silent`:   modem reports attached but probe failed — "attached but unreachable."
    /// - `overt`:    NWPath reported a path loss — system-acknowledged cellular drop.
    /// - `stall`:    throughput effectively zero though reachability succeeds.
    /// - `degraded`: slow-but-not-dropped (slowThroughput, or probeSuccess with high latency).
    /// - `drops`:    silent + overt + stall — all confirmed-unreachable or data-dead events.
    /// - `probes`:   total cellular probe-outcome events in the window.
    static func failureCounts(events: [ConnectivityEvent], since: Date?) -> FailureCounts {
        let w = windowed(events, since: since)

        let silent = w.filter { $0.eventType == .silentFailure && isCellular($0) }.count

        // `isDropEvent` already gates pathChange drops on cellular interface, so no additional
        // `isExpensive` check is needed — the function's own cellular discrimination is reused.
        let overt = w.filter { $0.eventType == .pathChange && isDropEvent($0) }.count

        // Stall = bulk-data-dead (severeThroughput) plus sustained-stream freezes (dataStall);
        // both are "reachable but unusable for real-time/bulk" and both count as drops.
        let stall = w.filter {
            ($0.eventType == .severeThroughput || $0.eventType == .dataStall) && isCellular($0)
        }.count

        let degradedSlow = w.filter { $0.eventType == .slowThroughput && isCellular($0) }.count
        let degradedSlowSuccess = w.filter {
            $0.eventType == .probeSuccess && isCellular($0)
                && ($0.probeLatencyMs ?? 0) > slowLatencyThresholdMs
        }.count
        let degraded = degradedSlow + degradedSlowSuccess

        let probes = w.filter { probeOutcomeTypes.contains($0.eventType) && isCellular($0) }.count

        return FailureCounts(
            silent: silent,
            overt: overt,
            stall: stall,
            degraded: degraded,
            drops: silent + overt + stall,
            probes: probes
        )
    }

    // MARK: - Time Window

    /// Returns the start of the last-24h window.
    /// Always call this instead of inlining 86400 elsewhere — centralised so UI and tests stay in sync.
    static func since24h() -> Date {
        Date().addingTimeInterval(-86400)
    }
}
