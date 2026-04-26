import SwiftUI
import SwiftData

struct SummaryReportView: View {
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var allEvents: [ConnectivityEvent]

    private var report: SummaryReport {
        SummaryReport.generate(from: allEvents)
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Total Drops", value: "\(report.totalDrops)")
                LabeledContent("Overt Drops", value: "\(report.overtDrops)")
                LabeledContent("Silent Failures", value: "\(report.silentDrops)")
                LabeledContent("Total Events", value: "\(report.totalEvents)")
                LabeledContent("Days Monitored", value: "\(report.monitoringDays) day\(report.monitoringDays == 1 ? "" : "s")")
            }
            Section("Stats") {
                if let ratio = report.dropRatio {
                    LabeledContent("Drop Ratio (Cellular)", value: String(format: "%.1f%%", ratio * 100))
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
