#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only seeding of a curated, realistic `ConnectivityEvent` dataset for visual verification.
///
/// Triggered by launching the app with the `--seed-mock-data` argument (wired in CellGuardApp.init).
/// Wipes existing events first, then inserts a known spread covering every event/failure mode so
/// every screen can be screenshotted with deterministic data instead of waiting for live captures.
/// Never compiled into release builds.
enum MockData {
    static func seed(into context: ModelContext) {
        try? context.delete(model: ConnectivityEvent.self)

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let nr = "CTRadioAccessTechnologyNRNSA"
        let clusterA = (lat: 47.3769, lon: 8.5417)   // Zürich HB
        let clusterB = (lat: 47.3925, lon: 8.5210)   // Zürich West

        var events: [ConnectivityEvent] = []

        // Healthy reachability successes (fast latency)
        for (i, latency) in stride(from: 90.0, through: 430.0, by: 28.0).enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 33 + 5), eventType: .probeSuccess, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, carrierName: "Swisscom",
                vpnState: .connected, vpnInterface: "utun6", probeLatencyMs: latency,
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // Slow-but-successful reachability (degradation signal, under the 12s ceiling)
        for (i, latency) in [3200.0, 6100.0, 9300.0].enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 80 + 40), eventType: .probeSuccess, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, carrierName: "Swisscom",
                vpnState: .connected, vpnInterface: "utun6", probeLatencyMs: latency,
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // Healthy throughput samples
        for (i, kbps) in [42000.0, 31000.0, 18500.0, 9200.0].enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 120 + 20), eventType: .probeSuccess, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, vpnState: .connected, vpnInterface: "utun6",
                throughputKbps: kbps, latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // Silent failures (headline evidence)
        for i in 0..<8 {
            let cl = i % 3 == 0 ? clusterB : clusterA
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 95 + 25), eventType: .silentFailure, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, carrierName: "Swisscom",
                vpnState: .connected, vpnInterface: "utun6", probeLatencyMs: 10000 + Double(i),
                latitude: cl.lat, longitude: cl.lon, locationAccuracy: 70, dropDurationSeconds: Double(40 + i * 12)))
        }
        // Overt drops (cellular path unsatisfied — system-acknowledged)
        for i in 0..<4 {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 160 + 60), eventType: .pathChange, pathStatus: .unsatisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr,
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 70, dropDurationSeconds: Double(8 + i * 5)))
        }
        // Wi-Fi handover gaps (NOT drops — interface wifi)
        for i in 0..<2 {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 200 + 90), eventType: .pathChange, pathStatus: .unsatisfied,
                interfaceType: .wifi))
        }
        // Slow throughput (degraded, not a drop)
        for (i, kbps) in [870.0, 540.0, 300.0].enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 140 + 50), eventType: .slowThroughput, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, vpnState: .connected, vpnInterface: "utun6",
                throughputKbps: kbps, latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // Severe throughput (NEW — counts as a drop)
        for (i, kbps) in [180.0, 120.0, 70.0, 45.0].enumerated() {
            let cl = i % 2 == 0 ? clusterA : clusterB
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 110 + 35), eventType: .severeThroughput, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, vpnState: .connected, vpnInterface: "utun6",
                throughputKbps: kbps, latitude: cl.lat, longitude: cl.lon, locationAccuracy: 65))
        }
        // Probe failures
        for i in 0..<2 {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 175 + 80), eventType: .probeFailure, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, probeLatencyMs: 10000 + Double(i * 5),
                probeFailureReason: "timeout"))
        }
        // Radio-technology transitions (NEW — the radio-layer oscilloscope; NRNSA↔LTE flips)
        for (i, tech) in ["CTRadioAccessTechnologyLTE", nr, "CTRadioAccessTechnologyLTE"].enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 70 + 15), eventType: .radioTechChange, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: tech,
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // User-reported incidents (NEW — one-tap ground truth, e.g. a dropped WhatsApp call)
        for i in 0..<2 {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 130 + 45), eventType: .userIncident, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr,
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65))
        }
        // Data stalls (NEW — sustained-stream freezes; counts as a drop)
        for (i, stallSec) in [2.4, 4.1, 7.8].enumerated() {
            events.append(ConnectivityEvent(
                timestamp: ago(Double(i) * 150 + 55), eventType: .dataStall, pathStatus: .satisfied,
                interfaceType: .cellular, isExpensive: true, pathUsesCellular: true, radioTechnology: nr, vpnState: .connected, vpnInterface: "utun6",
                probeFailureReason: "stream froze mid-transfer",
                latitude: clusterA.lat, longitude: clusterA.lon, locationAccuracy: 65, dropDurationSeconds: stallSec))
        }

        for event in events { context.insert(event) }
        try? context.save()
    }
}
#endif
