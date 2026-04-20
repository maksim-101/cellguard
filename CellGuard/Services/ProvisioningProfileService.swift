import Observation
import Foundation
import UserNotifications

/// Reads the embedded provisioning profile to detect expiration date and schedules
/// a local notification 7 days before certificate expiry.
///
/// On the iOS Simulator, embedded.mobileprovision does not exist, so all properties
/// gracefully return nil/fallback values.
///
/// With paid Apple Developer Program signing (Team VTWHBCCP36), the provisioning
/// profile is valid for ~1 year. The 7-day warning gives time to re-deploy from Xcode.
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

    /// Whether the expiry date is estimated from build date (profile file not readable).
    private(set) var isEstimatedExpiry: Bool = false

    // MARK: - Computed Properties

    /// Whether the profile expires within 7 days.
    var isExpiringSoon: Bool {
        guard let expirationDate else { return false }
        return expirationDate.timeIntervalSinceNow < 7 * 24 * 3600
    }

    /// Human-readable expiration date for display in the UI.
    /// Returns "Unknown (Simulator)" when the profile is unavailable.
    var expirationDisplayText: String {
        guard let expirationDate else {
            return "Unknown (Simulator)"
        }
        let formatted = expirationDate.formatted(.dateTime.month().day().year())
        return isEstimatedExpiry ? "\(formatted) (est.)" : formatted
    }

    /// Number of days until profile expiry, or nil if expiration date is unknown.
    var daysUntilExpiry: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    // MARK: - Profile Loading

    /// Reads the embedded.mobileprovision file and extracts the expiration date.
    ///
    /// Tries two lookup strategies for the profile file:
    /// 1. Standard `Bundle.main.path(forResource:ofType:)` resource lookup
    /// 2. Direct path construction at bundle root (iOS 26 + paid signing workaround)
    ///
    /// If neither finds the file (Simulator, or profile not embedded), falls back to
    /// estimating expiry from the executable's build date + 1 year.
    func loadProfile() {
        // Strategy 1: standard resource lookup
        var profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision")

        // Strategy 2: direct path at bundle root (iOS 26 may not surface via resource lookup)
        if profilePath == nil {
            let directPath = Bundle.main.bundlePath + "/embedded.mobileprovision"
            if FileManager.default.fileExists(atPath: directPath) {
                profilePath = directPath
            }
        }

        if let path = profilePath {
            parseProfile(at: path)
        } else {
            // Fallback: estimate expiry from build date (paid dev cert = ~1 year)
            estimateExpiryFromBuildDate()
        }
    }

    /// Parses the CMS/PKCS#7 provisioning profile at the given path.
    private func parseProfile(at path: String) {
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
            isEstimatedExpiry = false

            // Schedule notification if we have a valid expiration date
            scheduleExpiryNotification()
        } catch {
            print("Failed to read provisioning profile: \(error)")
            estimateExpiryFromBuildDate()
        }
    }

    /// Estimates certificate expiry from the executable's build date.
    /// Paid Apple Developer certificates are valid for ~1 year.
    private func estimateExpiryFromBuildDate() {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let buildDate = attrs[.modificationDate] as? Date else {
            expirationDate = nil
            profileName = nil
            return
        }

        expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: buildDate)
        profileName = "Estimated (paid team)"
        isEstimatedExpiry = true
        scheduleExpiryNotification()
    }

    // MARK: - Notification Scheduling

    /// Schedules a local notification 7 days before the provisioning profile expires.
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

            // Calculate 7 days before expiration
            let warningDate = expirationDate.addingTimeInterval(-7 * 24 * 3600)

            // If we're already past the warning window, don't schedule
            guard warningDate > Date() else { return }

            let content = UNMutableNotificationContent()
            content.title = "CellGuard Certificate Expiring"
            content.body = "Your Developer certificate expires in 7 days. Deploy the app from Xcode to renew it and continue monitoring."
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
