import SwiftUI
import SwiftData

struct SummaryReportView: View {
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var allEvents: [ConnectivityEvent]

    @State private var showRatioInfo = false

    private var report: SummaryReport {
        SummaryReport.generate(from: allEvents)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Total Drops", value: "\(report.totalDrops)")
                LabeledContent("Overt Drops", value: "\(report.overtDrops)")
                LabeledContent("Silent Failures", value: "\(report.silentDrops)")
                LabeledContent("Data Stalls", value: "\(report.stallDrops)")
                LabeledContent("Total Events", value: "\(report.totalEvents)")
                LabeledContent("Days Monitored", value: "\(report.monitoringDays) day\(report.monitoringDays == 1 ? "" : "s")")
            } header: {
                Text("Overview")
            } footer: {
                Text("Total Drops = Overt + Silent + Data Stalls. Degraded events (below) are slow but not lost, so they are not counted as drops.")
            }
            Section("Degraded (not drops)") {
                LabeledContent("Slow / degraded probes", value: "\(report.degradedCount)")
            }
            Section("Stats") {
                if let ratio = report.dropRatio {
                    HStack {
                        LabeledContent("Drop Ratio (Cellular)", value: String(format: "%.1f%%", ratio * 100))
                        Button {
                            showRatioInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .popover(isPresented: $showRatioInfo) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Drop Ratio")
                                    .font(.headline)
                                Text("The percentage of cellular connectivity attempts that resulted in a drop.")
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Denominator: cellular probe attempts + overt drops")
                                    Text("Numerator: Total Drops (Silent + Overt + Data Stalls)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(20)
                            .frame(idealWidth: 280, maxWidth: 320)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                if let degradedRatio = report.degradedRatio {
                    LabeledContent("Degraded Ratio (Cellular)", value: String(format: "%.1f%%", degradedRatio * 100))
                }
                LabeledContent("Drops per Day", value: String(format: "%.1f", report.dropsPerDay))
            }
            Section("Duration") {
                if let avg = report.averageDurationSeconds {
                    LabeledContent("Average Drop Duration", value: formatDuration(avg))
                }
                if let max = report.maxDurationSeconds {
                    LabeledContent("Max Drop Duration", value: formatDuration(max))
                }
            }
            Section("Radio Technology") {
                if report.radioDistribution.isEmpty {
                    Text("No radio data available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.radioDistribution, id: \.radio) { item in
                        LabeledContent(item.radio, value: "\(item.count)")
                    }
                }
            }
            Section("Location") {
                LabeledContent("Distinct Areas (~1km)", value: "\(report.locationClusters)")
            }
        }
        .navigationTitle("Summary Report")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
