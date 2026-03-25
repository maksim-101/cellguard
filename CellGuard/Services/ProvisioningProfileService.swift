import Observation
import Foundation
import UserNotifications

/// Reads the embedded provisioning profile to detect expiration date and schedules
/// a local notification 48 hours before profile expiry.
///
/// On the iOS Simulator, embedded.mobileprovision does not exist, so all properties
/// gracefully return nil/fallback values (Pitfall 6 from research).
///
/// The 7-day free personal team re-sign cycle means profile expiry awareness is critical
/// to prevent silent monitoring stoppage when the app is no longer launchable.
@Observable
final class ProvisioningProfileService {

    // MARK: - Nested Types

    /// Decodable representation of the provisioning profile plist.
    private struct ProvisioningProfile: Decodable {
        let name: String
        let expirationDate: Date
        let creationDate: Date

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case expirationDate = "ExpirationDate"
            case creationDate = "CreationDate"
        }
    }

    // MARK: - Properties

    /// Expiration date of the embedded provisioning profile.
    /// Nil on Simulator or if the profile cannot be read.
    private(set) var expirationDate: Date?

    /// Name of the provisioning profile (e.g., "iOS Team Provisioning Profile: com.cellguard").
    private(set) var profileName: String?

    // MARK: - Computed Properties

    /// Whether the profile expires within 48 hours.
    var isExpiringSoon: Bool {
        guard let expirationDate else { return false }
        return expirationDate.timeIntervalSinceNow < 48 * 3600
    }

    /// Human-readable expiration date for display in the UI.
    /// Returns "Unknown (Simulator)" when the profile is unavailable.
    var expirationDisplayText: String {
        guard let expirationDate else {
            return "Unknown (Simulator)"
        }
        return expirationDate.formatted(.dateTime.month().day().year())
    }

    /// Number of days until profile expiry, or nil if expiration date is unknown.
    var daysUntilExpiry: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    // MARK: - Profile Loading

    /// Reads the embedded.mobileprovision file and extracts the expiration date.
    ///
    /// On the Simulator, the file does not exist and `expirationDate` remains nil.
    /// On a real device, the provisioning profile plist is extracted from the binary
    /// DER-encoded file by locating the XML plist section.
    func loadProfile() {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else {
            // Simulator or missing profile -- graceful fallback
            expirationDate = nil
            profileName = nil
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))

            // The mobileprovision file is a CMS/PKCS#7 signed container.
            // The plist XML is embedded within it as ASCII text.
            guard let asciiString = String(data: data, encoding: .ascii) else {
                expirationDate = nil
                return
            }

            // Extract the plist XML from the binary container
            guard let xmlStart = asciiString.range(of: "<?xml"),
                  let plistEnd = asciiString.range(of: "</plist>") else {
                expirationDate = nil
                return
            }

            let plistRange = xmlStart.lowerBound..<plistEnd.upperBound
            let plistString = String(asciiString[plistRange])

            guard let plistData = plistString.data(using: .utf8) else {
                expirationDate = nil
                return
            }

            let decoder = PropertyListDecoder()
            let profile = try decoder.decode(ProvisioningProfile.self, from: plistData)

            expirationDate = profile.expirationDate
            profileName = profile.name

            // Schedule notification if we have a valid expiration date
            scheduleExpiryNotification()
        } catch {
            print("Failed to read provisioning profile: \(error)")
            expirationDate = nil
            profileName = nil
        }
    }

    // MARK: - Notification Scheduling

    /// Schedules a local notification 48 hours before the provisioning profile expires.
    ///
    /// Requests notification authorization if not already granted. Replaces any
    /// previously scheduled "profileExpiry" notification.
    private func scheduleExpiryNotification() {
        guard let expirationDate else { return }

        let center = UNUserNotificationCenter.current()

        // Request authorization (no-op if already granted)
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted, error == nil else { return }

            // Remove any previously scheduled expiry notification
            center.removePendingNotificationRequests(withIdentifiers: ["profileExpiry"])

            // Calculate 48 hours before expiration
            let warningDate = expirationDate.addingTimeInterval(-48 * 3600)

            // If we're already past the warning window, don't schedule
            guard warningDate > Date() else { return }

            let content = UNMutableNotificationContent()
            content.title = "CellGuard Profile Expiring"
            content.body = "Your provisioning profile expires in 48 hours. Re-sign the app in Xcode to continue monitoring."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(warningDate.timeIntervalSinceNow, 1),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "profileExpiry",
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error {
                    print("Failed to schedule profile expiry notification: \(error)")
                }
            }
        }
    }
}
