import Foundation

/// Pure classification rule for the severe-latency drop tier.
///
/// **Why throughput, not signal strength.** iOS exposes no public signal-strength API anywhere in
/// the iOS 26 SDK. Private ones (`CTGetSignalStrength`, status-bar scraping) are rejected: this
/// app's JSON export is evidence in an Apple engineering escalation, and a diagnostic tool that
/// reads undocumented internals hands Apple a free way to dismiss the entire dataset. Throughput is
/// the honest proxy instead, because weak signal degrades latency AND throughput together (physics),
/// while a modem stall degrades latency alone — a radio that just proved it can move data fast is
/// not the same failure as one sitting on one bar in a basement.
///
/// **The rule's contract (four branches):**
/// | latency | recent throughput reference | classification |
/// |---|---|---|
/// | > 5000 ms | healthy (>= healthyThroughputKbps), fresh | severe — the radio was demonstrably capable |
/// | > 5000 ms | poor (< healthyThroughputKbps), fresh | NOT severe — consistent with weak signal |
/// | > 5000 ms | absent OR stale | NOT severe — capability unproven, so no claim is made |
/// | <= 5000 ms | anything | NOT severe — clean success |
enum SevereLatencyRule {
    /// A probe taking longer than this counts as slow. Below this it is a clean success regardless
    /// of throughput.
    static let severeLatencyThresholdMs: Double = 5000

    /// Returns true only when a slow probe ran over a radio that JUST proved it can move data fast.
    /// Any missing or stale reference is treated conservatively (not severe) — see the contract above.
    static func isSevere(
        latencyMs: Double?,
        referenceThroughputKbps: Double?,
        referenceAge: TimeInterval?,
        freshnessWindow: TimeInterval,
        healthyThroughputKbps: Double
    ) -> Bool {
        guard let latencyMs, latencyMs > severeLatencyThresholdMs else { return false }
        guard let referenceThroughputKbps, let referenceAge, referenceAge <= freshnessWindow else {
            return false
        }
        return referenceThroughputKbps >= healthyThroughputKbps
    }
}
