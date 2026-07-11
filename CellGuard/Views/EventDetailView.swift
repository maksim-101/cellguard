import SwiftUI

/// Full metadata detail view for a single ConnectivityEvent (UI-03).
///
/// Displays all captured metadata organized into labeled sections.
/// Conditional sections appear only when the relevant data exists
/// (probe results, location, drop duration).
struct EventDetailView: View {
    let event: ConnectivityEvent

    var body: some View {
        List {
            Section("Event") {
                LabeledContent("Type", value: event.eventType.displayName)
                LabeledContent("Time", value: event.timestamp.formatted(.dateTime))
            }

            Section("Network") {
                LabeledContent("Path Status", value: event.pathStatus.displayName)
                LabeledContent("Interface", value: event.interfaceType.displayName)
                LabeledContent("Expensive", value: event.isExpensive ? "Yes" : "No")
                LabeledContent("Constrained", value: event.isConstrained ? "Yes" : "No")
                LabeledContent("Low Power Mode", value: event.lowPowerMode ? "On" : "Off")
            }

            Section("Cellular") {
                LabeledContent("Radio Tech (data line)", value: radioTechDisplay)
                if let restriction = event.cellularDataRestricted, restriction != "unknown" {
                    LabeledContent("Cellular Data Access", value: restriction)
                }
                if let kbps = event.throughputKbps {
                    LabeledContent("Throughput", value: String(format: "%.1f Mbps", kbps / 1000))
                }
            }

            // Multi-SIM / DSDS per-service radio state (DSDS-01/02/03). Shown only when the
            // event actually captured per-service data -- legacy events (both fields nil) render
            // exactly as before, no empty section or placeholder.
            if let services = event.radioServices, !services.isEmpty {
                Section("SIM Services") {
                    if let changed = event.radioChangeService {
                        LabeledContent("Changed Line", value: changed)
                    }
                    ForEach(services, id: \.service) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(snapshot.isPrimary ? "Data Line" : "Other Line")
                                Spacer()
                                // A service with no radio tech is provisioned but registered on
                                // NO network -- this must always render explicitly, never as
                                // blank or "Unknown", because that absence IS the evidence.
                                Text(radioTechDisplay(for: snapshot.tech))
                            }
                            Text(snapshot.service)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if event.wifiSSID != nil {
                Section("Wi-Fi") {
                    LabeledContent("SSID", value: event.wifiSSID?.isEmpty == true ? "\u{2014}" : event.wifiSSID!)
                }
            }

            // Show VPN section for any event that captured VPN state (Phase 8+).
            // Legacy events with vpnState == nil (never captured) are omitted.
            // Disconnected events show explicitly so absence is unambiguous in evidence logs.
            if let state = event.vpnState {
                Section("VPN") {
                    LabeledContent("State", value: state.displayName)
                    LabeledContent("Interface", value: event.vpnInterface ?? "None")
                }
            }

            if event.probeLatencyMs != nil || event.probeFailureReason != nil || event.referenceThroughputKbps != nil {
                Section("Probe") {
                    if let latency = event.probeLatencyMs {
                        LabeledContent("Latency", value: String(format: "%.0f ms", latency))
                    }
                    // The audit trail for the severe-latency rule: says either "this probe was
                    // called a drop because the radio measured N Mbps shortly before" or "this
                    // slow probe was NOT called a drop because the radio measured only N Mbps".
                    // Nil (legacy events, or no throughput sample was fresh at capture time) renders
                    // no row at all -- never an empty placeholder.
                    if let referenceKbps = event.referenceThroughputKbps {
                        LabeledContent("Reference Throughput", value: String(format: "%.1f Mbps", referenceKbps / 1000))
                    }
                    if let reason = event.probeFailureReason {
                        LabeledContent("Failure Reason", value: reason)
                    }
                }
            }

            if event.latitude != nil {
                Section("Location") {
                    if let lat = event.latitude {
                        LabeledContent("Latitude", value: String(format: "%.4f", lat))
                    }
                    if let lon = event.longitude {
                        LabeledContent("Longitude", value: String(format: "%.4f", lon))
                    }
                    if let accuracy = event.locationAccuracy {
                        LabeledContent("Accuracy", value: String(format: "%.0f m", accuracy))
                    }
                }
            }

            if let duration = event.dropDurationSeconds {
                Section("Duration") {
                    LabeledContent("Drop Duration", value: formatDuration(duration))
                }
            }
        }
        .navigationTitle(event.eventType.displayName)
    }

    // MARK: - Computed Helpers

    /// Strips the "CTRadioAccessTechnology" prefix from a raw radio tech string for cleaner
    /// display (e.g., "NR" instead of "CTRadioAccessTechnologyNR"). Shared by both the
    /// top-level "Radio Tech (data line)" row and the per-service "SIM Services" section.
    private func stripRadioTechPrefix(_ tech: String) -> String {
        tech.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
    }

    private var radioTechDisplay: String {
        guard let tech = event.radioTechnology else { return "Unknown" }
        return stripRadioTechPrefix(tech)
    }

    /// Per-service display: nil means the service is provisioned but registered on NO
    /// network -- rendered as an explicit "Not registered", never blank or "Unknown", because
    /// that ambiguity would erase the exact signal this feature exists to surface.
    private func radioTechDisplay(for tech: String?) -> String {
        guard let tech else { return "Not registered" }
        return stripRadioTechPrefix(tech)
    }

    /// Formats a duration in seconds as a human-readable string.
    /// Examples: "2h 15m 30s", "5m 12s", "45s"
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Display Name Extensions

extension PathStatus {
    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .satisfied: "Satisfied"
        case .unsatisfied: "Unsatisfied"
        case .requiresConnection: "Requires Connection"
        }
    }
}

extension InterfaceType {
    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .cellular: "Cellular"
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .loopback: "Loopback"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}

extension VPNState {
    /// Human-readable name for UI display. Per UI-SPEC §Copywriting Contract,
    /// `Reconnecting` is the human-readable mapping for `.reasserting`; the
    /// internal Apple-API word "reasserting" is never exposed to users.
    var displayName: String {
        switch self {
        case .invalid: "Invalid"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reasserting: "Reconnecting"
        case .disconnecting: "Disconnecting"
        }
    }
}
