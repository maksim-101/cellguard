import SwiftUI

struct HealthDetailSheet: View {
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(LocationService.self) private var locationService
    @Environment(MonitoringHealthService.self) private var healthService
    @Environment(ProvisioningProfileService.self) private var profileService
    @Environment(\.dismiss) private var dismiss

    @State private var sheetDetent: PresentationDetent = .large

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

                    // Last background wake — live ticker (POLISH-01 / D-09)
                    // TimelineView re-renders this subview every 1s while the sheet is visible.
                    // SwiftUI scopes the re-render to the closure body and stops automatically
                    // when the view disappears, so there is no Combine subscription or Timer
                    // lifecycle to manage.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last Background Wake:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lastBackgroundWakeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            
                            Text("Records wakes from Significant Location Changes while the app is in the background.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .presentationDetents([.medium, .large], selection: $sheetDetent)
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

    /// Relative-time string for the most recent BACKGROUND wake (POLISH-01 / D-10).
    /// Reads `lastBackgroundWakeTimestamp` (written only by `LocationService` when
    /// `applicationState != .active`). When the key is unset / zero, returns the
    /// locked empty-state copy so the user sees an unambiguous signal that the
    /// app has not yet been woken in the background.
    private var lastBackgroundWakeText: String {
        let raw = UserDefaults.standard.double(forKey: AppDefaultsKeys.lastBackgroundWakeTimestamp)
        guard raw > 0 else { return "Never (no background wake yet)" }
        let wakeDate = Date(timeIntervalSince1970: raw)
        return wakeDate.formatted(
            .relative(presentation: .named, unitsStyle: .abbreviated)
        )
    }
}
