import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// Transferable wrapper that encodes ConnectivityEvent arrays to JSON for ShareLink export (EXP-01).
///
/// Usage: ShareLink(item: EventLogExport(events: allEvents), preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text")))
///
/// Writes a pretty-printed, sorted-keys JSON file to the temp directory. The filename includes
/// a date stamp for uniqueness: "cellguard-events-2026-03-25.json".
struct EventLogExport: Transferable {
    let events: [ConnectivityEvent]
    let omitLocation: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if export.omitLocation {
                encoder.userInfo[.omitLocation] = true
            }
            let data = try encoder.encode(export.events)

            let dateString = ISO8601DateFormatter().string(from: Date())
                .prefix(10) // "2026-03-25"
            let filename = "cellguard-events-\(dateString).json"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
