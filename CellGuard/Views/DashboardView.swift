import SwiftUI
import SwiftData

/// Main landing screen — Option H "Cellular Health" layout.
/// Shows two ScoreRings (Overall + Last 24h), a verdict pill, a 24h probe-count row,
/// and a failure-mode breakdown, followed by the standard navigation links.
struct DashboardView: View {
    @Environment(ConnectivityMonitor.self) private var monitor
    @Environment(MonitoringHealthService.self) private var healthService

    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var allEvents: [ConnectivityEvent]

    @State private var showHealthSheet = false
    @AppStorage("omitLocationData") private var omitLocation = false

    // MARK: - HealthScore Derived Values

    private var overall: Double? {
        HealthScore.score(events: allEvents, since: nil)
    }

    private var last24h: Double? {
        HealthScore.score(events: allEvents, since: HealthScore.since24h())
    }

    private var counts24h: HealthScore.FailureCounts {
        HealthScore.failureCounts(events: allEvents, since: HealthScore.since24h())
    }

    private var verdict: (text: String, symbol: String, color: Color)? {
        HealthScore.verdict(last24h: last24h, overall: overall)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Health status bar (tappable, opens detail sheet)
            healthBar
                .padding(.bottom, 6)

            // Card 1: Cellular Health — two ScoreRings + verdict pill
            cellularHealthCard
                .padding(.horizontal)
                .padding(.bottom, 6)

            // Card 2: 24h probe/drop/degraded count row
            probeCountRow
                .padding(.horizontal)
                .padding(.bottom, 6)

            // Card 3: 24h failure-mode breakdown
            failureModeCard
                .padding(.horizontal)
                .padding(.bottom, 6)

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
                .padding(.vertical, 6)
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
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 4)

            // Navigation to analytics (ANALYTICS-01)
            NavigationLink {
                AnalyticsView(events: allEvents)
            } label: {
                HStack {
                    Label("Location Analytics", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
                .padding(.vertical, 6)
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
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Spacer(minLength: 40)
        }
        .navigationTitle("CellGuard")
        .navigationBarTitleDisplayMode(.inline)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monitoring \(healthAccessibilityLabel), tap for details")
    }

    // MARK: - Cellular Health Card (Card 1)

    private var cellularHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cellular Health")
                    .font(.headline)
                Spacer()
                Text("Wi-Fi excluded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Spacer()
                ScoreRing(score: overall, label: "Overall")
                Spacer()
                ScoreRing(score: last24h, label: "Last 24h")
                Spacer()
            }

            if let v = verdict {
                HStack {
                    Spacer()
                    Label(v.text, systemImage: v.symbol)
                        .foregroundStyle(v.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(v.color.opacity(0.15)))
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Probe Count Row (Card 2)

    private var probeCountRow: some View {
        HStack {
            Text("Last 24 h")
                .foregroundStyle(.secondary)
            Spacer()
            (Text("\(counts24h.probes) probes · ")
             + Text("\(counts24h.drops)").foregroundStyle(.red)
             + Text(" drops · ")
             + Text("\(counts24h.degraded)").foregroundStyle(.yellow)
             + Text(" degraded"))
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Failure Mode Card (Card 3)

    private var failureModeCard: some View {
        VStack(spacing: 8) {
            failureRow(color: .red,             name: "Silent",   subtitle: "unreachable",     count: counts24h.silent)
            Divider()
            failureRow(color: .orange,          name: "Overt",    subtitle: "system loss",     count: counts24h.overt)
            Divider()
            failureRow(color: Color(.systemPurple), name: "Stall", subtitle: "data dead",      count: counts24h.stall)
            Divider()
            failureRow(color: .yellow,          name: "Degraded", subtitle: "slow, not a drop", count: counts24h.degraded)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func failureRow(color: Color, name: String, subtitle: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .bold()
        }
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

// MARK: - ScoreRing

private struct ScoreRing: View {
    let score: Double?
    let label: String

    private var band: (label: String, color: Color)? {
        score.map { HealthScore.band(for: $0) }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                if let score, let band {
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(band.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(score.rounded()))")
                            .font(.title.bold())
                        Text(band.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("—")
                            .font(.title.bold())
                        Text("No data")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 88, height: 88)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
