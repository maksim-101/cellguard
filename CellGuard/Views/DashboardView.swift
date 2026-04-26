import SwiftUI
import SwiftData
import Charts

/// Main landing screen showing monitoring status, connectivity state,
/// drop counts (24h/7d/total), and last drop timestamp (UI-01, UI-04).
struct DashboardView: View {
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(MonitoringHealthService.self) private var healthService

    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var allEvents: [ConnectivityEvent]

    @State private var showHealthSheet = false
    @AppStorage("omitLocationData") private var omitLocation = false

    var body: some View {
        VStack(spacing: 0) {
            // Health status bar (tappable, opens detail sheet)
            healthBar
                .padding(.bottom, 8)

            // Current connectivity state
            connectivityStateCard
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Drop count cards
            dropCountCards
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Last drop timestamp
            lastDropRow
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Drop timeline chart (EXP-03)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop Timeline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                DropTimelineChart(events: allEvents)
                    .padding(.horizontal)
            }
            .padding(.bottom, 8)

            // Navigation to full event list
            NavigationLink {
                EventListView()
            } label: {
                HStack {
                    Label("View All Events", systemImage: "list.bullet")
                    Spacer()
                    Text("\(allEvents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 4)

            // Navigation to summary report (EXP-02)
            NavigationLink {
                SummaryReportView()
            } label: {
                HStack {
                    Label("Summary Report", systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 4)

            // Privacy toggle for export (EXPT-01, EXPT-03)
            Toggle("Omit location, Wi-Fi, and VPN data", isOn: $omitLocation)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 4)

            // Export event log as JSON via ShareLink (EXP-01)
            ShareLink(
                item: EventLogExport(events: allEvents, omitLocation: omitLocation, deviceModel: deviceModelIdentifier(), osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
                preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text"))
            ) {
                HStack {
                    Label("Export Event Log (JSON)", systemImage: "square.and.arrow.up")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Spacer(minLength: 20)
        }
        .navigationTitle("CellGuard")
        .sheet(isPresented: $showHealthSheet) {
            HealthDetailSheet()
        }
    }

    // MARK: - Health Status Bar

    private var healthBar: some View {
        Button {
            showHealthSheet = true
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(healthDotColor)
                    .frame(width: 8, height: 8)
                Text(healthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let radio = monitor.currentRadioTechnology {
                    Text(radio.replacingOccurrences(of: "CTRadioAccessTechnology", with: ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monitoring \(healthAccessibilityLabel), tap for details")
    }

    // MARK: - Connectivity State Card

    private var connectivityStateCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.currentPathStatus.displayName)
                    .font(.headline)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Interface")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.effectiveInterfaceLabel)
                    .font(.headline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Drop Count Cards

    private var dropCountCards: some View {
        let dropEvents = allEvents.filter { isDropEvent($0) }
        let now = Date.now

        let count24h = dropEvents.filter { $0.timestamp >= now.addingTimeInterval(-86400) }.count
        let count7d = dropEvents.filter { $0.timestamp >= now.addingTimeInterval(-604800) }.count
        let countTotal = dropEvents.count

        return HStack(spacing: 12) {
            dropStatCard(count: count24h, label: "24h")
            dropStatCard(count: count7d, label: "7d")
            dropStatCard(count: countTotal, label: "Total")
        }
    }

    private func dropStatCard(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.largeTitle)
                .bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Last Drop Row

    private var lastDropRow: some View {
        let lastDrop = allEvents.first(where: { isDropEvent($0) })

        return HStack {
            Text("Last Drop")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let drop = lastDrop {
                Text(drop.timestamp, format: .dateTime)
                    .font(.subheadline)
            } else {
                Text("No drops recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Health Helpers

    private var healthDotColor: Color {
        switch healthService.health {
        case .active: .green
        case .degraded: .orange
        case .paused: .red
        }
    }

    private var healthLabel: String {
        switch healthService.health {
        case .active: "Monitoring Active"
        case .degraded: "Monitoring Degraded"
        case .paused: "Monitoring Paused"
        }
    }

    private var healthAccessibilityLabel: String {
        switch healthService.health {
        case .active: "active"
        case .degraded: "degraded"
        case .paused: "paused"
        }
    }
}
