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

    /// Heartbeat: epoch seconds of the last moment we KNOW the app was alive and monitoring.
    /// Written by ConnectivityMonitor on every logged event (any probe, path change, etc.) AND
    /// by LocationService on every wake — NOT only on location wakes. Gap detection measures
    /// "now − lastActive", so writing it on every probe is what keeps monitoringGap durations
    /// honest (previously foreground/BG probes left it stale and gaps were massively overcounted).
    /// Value string kept as "lastActiveTimestamp" so existing installs' stored value carries over.
    static let lastActiveTimestamp = "lastActiveTimestamp"

    /// Opt-in "Intensive Capture" flag. When true, LocationService holds a continuous low-accuracy
    /// location session to keep the process alive while stationary, and the 60s probe timer is kept
    /// running in the background. Costs battery + shows the persistent location indicator.
    static let intensiveCaptureEnabled = "intensiveCaptureEnabled"
}
