import Foundation

/// Single source of truth for UserDefaults keys shared across multiple files.
///
/// Phase 9 / MN-01: previously `"lastBackgroundWakeTimestamp"` was duplicated
/// between the writer (`LocationService`) and the reader (`HealthDetailSheet`).
/// A typo on either side would silently break the live wake row with no compile
/// error. Cross-file UserDefaults keys MUST go through this enum from now on.
///
/// Keys that are SINGLE-FILE scope (e.g. LocationService's `monitoringEnabled`
/// and `lastActiveTimestamp`) intentionally stay in their file-local
/// `DefaultsKey` nested enum — promoting them here would just add noise.
enum AppDefaultsKeys {
    /// Set ONLY when a CoreLocation significant-location-change callback fires
    /// while `UIApplication.shared.applicationState != .active` (POLISH-01 / D-08).
    /// Read by HealthDetailSheet's TimelineView-wrapped wake row.
    static let lastBackgroundWakeTimestamp = "lastBackgroundWakeTimestamp"
}
