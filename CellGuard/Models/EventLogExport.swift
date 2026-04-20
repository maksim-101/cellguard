import SwiftUI
import UniformTypeIdentifiers
import Foundation
import CoreTelephony

// MARK: - Export Metadata

/// Device and collection metadata included in the top-level JSON export envelope.
private struct ExportMetadata: Codable {
    let appName: String
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let osVersion: String
    let carrier: String?
    let collectionPeriod: CollectionPeriod?
    let totalEvents: Int
    let totalDrops: Int
    let exportDate: Date
    let locationDataIncluded: Bool
}

/// Start and end timestamps of the event collection window.
private struct CollectionPeriod: Codable {
    let start: Date
    let end: Date
}

// MARK: - Top-Level Export Wrapper

/// Top-level JSON structure: `{ "metadata": {...}, "events": [...] }`.
private struct CellGuardExport: Codable {
    let metadata: ExportMetadata
    let events: [ConnectivityEvent]
}

// MARK: - EventLogExport (public interface unchanged)

/// Transferable wrapper that encodes ConnectivityEvent arrays to JSON for ShareLink export (EXP-01).
///
/// Usage: ShareLink(item: EventLogExport(events: allEvents, omitLocation: false, deviceModel: deviceModelIdentifier(), osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"), preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text")))
///
/// Produces a pretty-printed JSON file with a metadata envelope containing device info, OS version,
/// carrier, collection period, event counts, and the events array. The filename includes a date stamp
/// for uniqueness: "cellguard-export-2026-03-25.json".
struct EventLogExport: Transferable, @unchecked Sendable {
    let events: [ConnectivityEvent]
    let omitLocation: Bool
    let deviceModel: String
    let osVersion: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if export.omitLocation {
                encoder.userInfo[.omitLocation] = true
            }

            // Build metadata envelope
            let sortedEvents = export.events.sorted { $0.timestamp < $1.timestamp }

            let collectionPeriod: CollectionPeriod?
            if let first = sortedEvents.first, let last = sortedEvents.last {
                collectionPeriod = CollectionPeriod(start: first.timestamp, end: last.timestamp)
            } else {
                collectionPeriod = nil
            }

            let info = Bundle.main.infoDictionary
            let appVersion = info?["CFBundleShortVersionString"] as? String ?? "unknown"
            let buildNumber = info?["CFBundleVersion"] as? String ?? "unknown"

            // Carrier name (deprecated iOS 16.0 with no replacement — best-effort)
            let carrierName = currentCarrierName()

            let metadata = ExportMetadata(
                appName: "CellGuard",
                appVersion: appVersion,
                buildNumber: buildNumber,
                deviceModel: export.deviceModel,
                osVersion: export.osVersion,
                carrier: carrierName,
                collectionPeriod: collectionPeriod,
                totalEvents: export.events.count,
                totalDrops: export.events.filter { isDropEvent($0) }.count,
                exportDate: Date(),
                locationDataIncluded: !export.omitLocation
            )

            let wrapper = CellGuardExport(metadata: metadata, events: sortedEvents)
            let data = try encoder.encode(wrapper)

            let dateString = ISO8601DateFormatter().string(from: Date())
                .prefix(10) // "2026-03-25"
            let filename = "cellguard-export-\(dateString).json"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Carrier Name (deprecated API, no replacement)

/// Returns the current carrier name. Deprecated iOS 16.0 with no replacement — best-effort per MON-05.
@available(iOS, deprecated: 16.0, message: "No replacement available from Apple")
private func currentCarrierName() -> String? {
    CTTelephonyNetworkInfo().serviceSubscriberCellularProviders?.values.first?.carrierName
}

// MARK: - Device Model Identifier

/// Returns the hardware model identifier (e.g. "iPhone17,4") rather than the marketing name.
func deviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(validatingCString: $0) ?? "Unknown"
        }
    }
}
