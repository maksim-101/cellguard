import SwiftUI

struct HealthDetailSheet: View {
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(LocationService.self) private var locationService
    @Environment(MonitoringHealthService.self) private var healthService
    @Environment(ProvisioningProfileService.self) private var profileService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Health status header
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(statusHeading)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                }

                // Status body text
                Text(statusBody)
                    .font(.body)

                // Degraded reasons list (if degraded)
                if case .degraded(let reasons) = healthService.health {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reason.rawValue)
                                        .font(.headline)
                                    Text(reason.fixInstruction)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Start/Stop button (if paused)
                if case .paused = healthService.health {
                    Button("Start Monitoring") {
                        monitor.startMonitoring()
                        locationService.startMonitoring()
                        healthService.evaluate(
                            isMonitoring: true,
                            locationAuth: locationService.authorizationStatus,
                            backgroundRefresh: UIApplication.shared.backgroundRefreshStatus
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else if monitor.isMonitoring {
                    Button("Stop Monitoring") {
                        monitor.stopMonitoring()
                        locationService.stopMonitoring()
                        healthService.evaluate(
                            isMonitoring: false,
                            locationAuth: locationService.authorizationStatus,
                            backgroundRefresh: UIApplication.shared.backgroundRefreshStatus
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                // Radio technology info
                if let radio = monitor.currentRadioTechnology {
                    let shortName = radio.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cellular Radio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(shortName) — \(radioDescription(shortName))")
                            .font(.subheadline)
                        Text("Modem registration, not active data connection. Shows even when on Wi-Fi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Footer metadata
                VStack(alignment: .leading, spacing: 4) {
                    // Certificate expiry
                    HStack {
                        Text("Cert Expires:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(profileService.expirationDisplayText)
                            .font(.caption)
                            .foregroundStyle(profileService.isExpiringSoon ? .red : .secondary)
                            .fontWeight(profileService.isExpiringSoon ? .bold : .regular)
                    }

                    // Last background wake
                    HStack {
                        Text("Last Background Wake:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastWakeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch healthService.health {
        case .active: .green
        case .degraded: .orange
        case .paused: .red
        }
    }

    private var statusHeading: String {
        switch healthService.health {
        case .active: "Monitoring Active"
        case .degraded: "Monitoring Degraded"
        case .paused: "Monitoring Paused"
        }
    }

    private var statusBody: String {
        switch healthService.health {
        case .active:
            "All systems operational. Background monitoring is running."
        case .degraded:
            "Background monitoring may miss events due to:"
        case .paused:
            "Monitoring is not running. Tap \"Start Monitoring\" to begin."
        }
    }

    private func radioDescription(_ shortName: String) -> String {
        switch shortName {
        case "NRNSA": return "5G Non-Standalone (LTE anchor)"
        case "NR": return "5G Standalone"
        case "LTE": return "4G LTE"
        case "WCDMA": return "3G WCDMA"
        case "HSDPA": return "3G HSDPA"
        case "HSUPA": return "3G HSUPA"
        case "CDMA1x": return "2G CDMA"
        case "CDMAEVDORev0", "CDMAEVDORevA", "CDMAEVDORevB": return "3G EV-DO"
        case "eHRPD": return "3G eHRPD"
        case "GPRS": return "2G GPRS"
        case "Edge": return "2G EDGE"
        default: return shortName
        }
    }

    private var lastWakeText: String {
        let lastActive = UserDefaults.standard.double(forKey: "lastActiveTimestamp")
        guard lastActive > 0 else { return "Never" }
        let lastDate = Date(timeIntervalSince1970: lastActive)
        return lastDate.formatted(.dateTime.hour().minute().second())
    }
}
