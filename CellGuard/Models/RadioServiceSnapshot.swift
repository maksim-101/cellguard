import Foundation

/// Per-service (multi-SIM / DSDS) radio access technology snapshot, captured at the same
/// instant as the rest of a ConnectivityEvent's metadata.
///
/// Foundation-only, no SwiftData/CoreTelephony import: this dependency-freedom is load-bearing
/// -- it lets a throwaway `swiftc` harness compile this exact production file standalone and
/// verify the encode/decode round-trip without a test target (this project has none).
struct RadioServiceSnapshot: Codable, Equatable {
    /// The opaque CoreTelephony service identifier (e.g. "0000000100000001"). Carries no
    /// subscriber/SIM/device identity -- it is a local slot handle, not an IMSI/ICCID/MSISDN.
    let service: String

    /// Radio access technology this service is registered on, e.g. "CTRadioAccessTechnologyNRNSA".
    /// nil means the service is PROVISIONED but registered on NO network -- this is the signal
    /// the whole feature exists to surface (a hunting/dead second line), so it must always be
    /// recorded explicitly rather than omitting the service from the array.
    let tech: String?

    /// True for the service iOS reports as the data-bearing line (see dataServiceIdentifier in
    /// ConnectivityMonitor). From this change onward, ConnectivityEvent.radioTechnology mirrors
    /// ONLY the primary line's tech -- a semantic narrowing of a field that previously held an
    /// arbitrary dictionary-iteration-order value across all services.
    let isPrimary: Bool
}

extension RadioServiceSnapshot {
    /// Compact single-line JSON encoding of a service list. `.sortedKeys` makes the output
    /// deterministic -- without it, two calls describing the identical radio state could produce
    /// different strings, making unchanged state look like a change downstream.
    /// Returns nil for an empty array: no cellular services means no data, not `"[]"`.
    static func encode(_ services: [RadioServiceSnapshot]) -> String? {
        guard !services.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(services) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Inverse of `encode(_:)`. nil in, nil out.
    static func decode(_ json: String?) -> [RadioServiceSnapshot]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([RadioServiceSnapshot].self, from: data)
    }
}
