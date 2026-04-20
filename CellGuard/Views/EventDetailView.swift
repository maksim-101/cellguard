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
            }

            Section("Cellular") {
                LabeledContent("Radio Tech", value: radioTechDisplay)
                LabeledContent("Carrier", value: event.carrierName ?? "Unknown")
            }

            if event.wifiSSID != nil {
                Section("Wi-Fi") {
                    LabeledContent("SSID", value: event.wifiSSID?.isEmpty == true ? "\u{2014}" : event.wifiSSID!)
                }
            }

            if event.probeLatencyMs != nil || event.probeFailureReason != nil {
                Section("Probe") {
                    if let latency = event.probeLatencyMs {
                        LabeledContent("Latency", value: String(format: "%.0f ms", latency))
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

    /// Strips the "CTRadioAccessTechnology" prefix from the raw radio tech string
    /// for cleaner display (e.g., "NR" instead of "CTRadioAccessTechnologyNR").
    private var radioTechDisplay: String {
        guard let tech = event.radioTechnology else { return "Unknown" }
        return tech.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
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
