<!-- GSD:project-start source:PROJECT.md -->
## Project

**CellGuard**

A lightweight iOS diagnostic app that continuously monitors cellular connectivity in the background and logs every detected drop with contextual metadata. Built as a personal tool to produce structured, timestamped evidence for an Apple Feedback Assistant report documenting persistent baseband modem failures on the iPhone 17 Pro Max.

**Core Value:** Reliably detect and log every cellular connectivity drop — including the "attached but unreachable" silent modem failure — so there is irrefutable evidence for Apple's engineering team.

### Constraints

- **Platform:** iOS 26.x, SwiftUI, Swift — must target iPhone 17 Pro Max specifically
- **Signing:** Free personal team (7-day re-sign cycle) — no entitlements requiring paid membership
- **Background execution:** Must use legitimate iOS background modes (Background App Refresh, NWPathMonitor background delivery, significant location changes) — no hacks that would cause termination
- **Battery:** Background monitoring must not cause noticeable battery drain
- **Storage:** All data local, no cloud — must handle weeks of event data without significant storage impact
- **Privacy:** No external data transmission whatsoever
- **Development:** Built with Claude Code — standard SwiftUI project structure
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Platform
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift | 6.2 (Xcode 26) | Language | Ships with iOS 26 SDK. Approachable Concurrency model simplifies async code. Strict concurrency checking catches data races at compile time. | HIGH |
| SwiftUI | iOS 26 SDK | UI framework | Project requirement. Native declarative UI with built-in support for Charts, NavigationStack, and observable state management. | HIGH |
| iOS 26 SDK | 26.x | Target platform | Project requirement. iPhone 17 Pro Max target device. | HIGH |
### Network Monitoring
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Network framework (`NWPathMonitor`) | iOS 12+ (stable) | Real-time path change detection | First-party framework for monitoring network path changes. Provides interface type, path status, DNS availability. Runs on background queue natively. No third-party wrapper needed -- the API is simple enough to use directly. | HIGH |
| `URLSession` (default config) | iOS 7+ (stable) | Active connectivity probing | HEAD requests to `captive.apple.com/hotspot-detect.html` every 60s to detect silent modem failures. Use default (not background) URLSession config -- background URLSession is designed for large transfers, not lightweight probes. The probe runs from within the app's background execution context, not from a suspended state. | HIGH |
### Cellular Metadata
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| CoreTelephony (`CTTelephonyNetworkInfo`) | iOS 12+ | Radio access technology detection | `serviceCurrentRadioAccessTechnology` returns current radio tech (LTE, NR/5G, 3G, etc.) per SIM service. Still functional in iOS 18+ SDK. The `serviceCurrentRadioAccessTechnologyDidChange` notification fires on radio tech changes. | MEDIUM |
| CoreTelephony (`CTCarrier`) | Deprecated iOS 16.4 | Carrier name | **Deprecated with no replacement.** Returns static/nil values when built with iOS 16.4+ SDK. However, `CTTelephonyNetworkInfo.serviceSubscriberCellularProviders` may still return carrier name on some devices/OS versions. Plan for this returning nil -- store "Unknown" as fallback. Test on actual iPhone 17 Pro Max with iOS 26 to verify. | LOW |
### Background Execution
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| CoreLocation (Significant Location Changes) | iOS 2+ | Background wake trigger + coarse location | **Primary background execution strategy.** `startMonitoringSignificantLocationChanges()` wakes the app on ~500m movement using cell tower triangulation. This is the only reliable way to get indefinite background execution without a paid developer account. The system will relaunch a terminated app for significant location changes. Requires "Always" location authorization. | HIGH |
| `NWPathMonitor` (background queue) | iOS 12+ | Path change callbacks while running | NWPathMonitor delivers callbacks on its assigned DispatchQueue while the app process is alive (foreground or background). It does NOT wake a suspended/terminated app -- it only works while the process is running. Combined with significant location changes keeping the process alive, this provides near-continuous monitoring. | HIGH |
| `BGAppRefreshTask` | iOS 13+ | Supplemental periodic wake | Register a background app refresh task as a secondary wake mechanism. System-discretionary timing (could be 15min to hours apart). Use this to run a connectivity probe when the app hasn't been woken by location changes. Not reliable as primary mechanism -- iOS throttles aggressively. | MEDIUM |
| `BGContinuedProcessingTask` | iOS 26+ | User-initiated export/report generation | New in iOS 26. Use ONLY for explicit user actions like CSV/JSON export or summary report generation. Requires user-initiated trigger, mandatory progress reporting, and user-cancellable UI. NOT suitable for background monitoring -- it requires explicit user action each time. | HIGH |
| `CLServiceSession` | iOS 18+ | Location authorization management | Required on iOS 18+ to ensure location updates are delivered. Must be retained for the lifetime of the location feature. Without an active CLServiceSession, background location delivery may silently stop. | HIGH |
### Location Services
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| CoreLocation (`CLLocationManager`) | iOS 2+ | Significant location changes | Use the legacy `CLLocationManager` API for significant location changes. The modern `CLMonitor` API (iOS 17+) has known stability issues, a 20-region limit, and documented crash bugs when monitors are recreated. CLLocationManager's significant location change API is battle-tested and reliable. | HIGH |
| `CLServiceSession` | iOS 18+ | Authorization + background delivery | Create and retain a CLServiceSession with `.always` authorization to ensure background location delivery works. Required for iOS 18+. | HIGH |
| `CLLocation` properties | iOS 2+ | Coarse location metadata | Extract `coordinate`, `horizontalAccuracy`, `timestamp` from location updates. Do NOT request high accuracy -- significant location changes already provides cell-tower-level accuracy (~500m), which is sufficient for geographic pattern analysis. | HIGH |
### Local Storage
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| SwiftData | iOS 17+ | Event log persistence | Use SwiftData because: (1) native SwiftUI integration with `@Query` for live UI updates, (2) `@Model` macro simplifies schema definition, (3) no external dependencies, (4) sufficient for this app's data volume (weeks of events = thousands of rows, not millions). Background writes via `@ModelActor` are well-documented. | MEDIUM |
- **vs. GRDB.swift:** GRDB is faster and more flexible, but adds an external dependency. SwiftData's performance is adequate for this use case (~1 event/minute = ~1,440 rows/day = ~10,000 rows/week). GRDB would be the right choice for high-throughput logging, but CellGuard's volume doesn't warrant it.
- **vs. Core Data:** SwiftData is built on Core Data. For a new project targeting iOS 26, there's no reason to use Core Data directly. SwiftData provides a cleaner API.
- **vs. Raw SQLite:** Unnecessary complexity for this use case. No custom SQL queries needed.
- **vs. UserDefaults/JSON files:** Not suitable for structured, queryable event logs.
### Data Export
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `ShareLink` (SwiftUI) | iOS 16+ | Share CSV/JSON files | Native SwiftUI component for sharing files via the system share sheet. No UIKit bridging needed. Generate file to temp directory, create `URL`, pass to `ShareLink`. | HIGH |
| `fileExporter()` (SwiftUI) | iOS 14+ | Save to Files app | Alternative export path. Lets user save directly to Files app / iCloud Drive. Implement `FileDocument` conformance for CSV and JSON formats. | HIGH |
| Foundation `JSONEncoder` | iOS 2+ | JSON serialization | Built-in. Encode `Codable` event models to JSON. | HIGH |
| Manual CSV generation | N/A | CSV serialization | No library needed. CSV is trivial to generate manually -- iterate events, format fields, join with commas. Properly escape fields containing commas/quotes. | HIGH |
| `BGContinuedProcessingTask` | iOS 26+ | Background export for large logs | If exporting weeks of data takes >5 seconds, use BGContinuedProcessingTask so the export continues if the user backgrounds the app. Requires progress reporting UI. | MEDIUM |
### Dashboard UI
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift Charts | iOS 16+ | Drop frequency visualization | First-party charting framework. Use `BarMark` for drops-per-hour/day, `LineMark` for trend lines. No external charting library needed. | HIGH |
| SwiftUI `NavigationStack` | iOS 16+ | Navigation | Standard navigation pattern. Dashboard -> Event List -> Event Detail. | HIGH |
| SwiftUI `@Observable` / `@Observation` | iOS 17+ | State management | Use the Observation framework (not ObservableObject). More efficient view updates, simpler syntax. `@Observable` class for monitoring service state. | HIGH |
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Storage | SwiftData | GRDB.swift | External dependency. Performance advantage not needed at CellGuard's data volume. |
| Storage | SwiftData | Realm | Heavy dependency, acquired by MongoDB, overkill for simple event logging. |
| Network monitoring | NWPathMonitor (direct) | Reachability.swift / Alamofire | Third-party wrappers add nothing -- NWPathMonitor API is already simple. Reachability is a legacy pattern. |
| Charts | Swift Charts | DGCharts (formerly Charts) | External dependency. Swift Charts covers all needed chart types (bar, line). |
| Background | Significant Location Changes | Continuous GPS | Massive battery drain. Not appropriate for 24+ hour monitoring. |
| Background | Significant Location Changes | BGProcessingTask only | System-discretionary. Could go hours between wakes. Not reliable for 60s probe intervals. |
| Location | CLLocationManager | CLMonitor (iOS 17+) | Documented crash bugs on monitor recreation. 20-region limit. Less battle-tested than CLLocationManager for significant location changes. |
| Concurrency | Swift Concurrency (async/await) | Combine | Combine is in maintenance mode. Swift Concurrency is the future. Use async/await with actors for thread safety. |
| Export | ShareLink + fileExporter | UIActivityViewController | UIKit bridge. ShareLink is the native SwiftUI equivalent. |
## Framework & Entitlement Requirements
### Info.plist Keys
### Capabilities in Xcode
### Frameworks to Import
## Project Structure
## Version Compatibility Matrix
| Framework | Minimum iOS | Target iOS | Notes |
|-----------|-------------|------------|-------|
| SwiftUI | 13.0 | 26.0 | NavigationStack requires 16+ |
| SwiftData | 17.0 | 26.0 | @ModelActor improved in 18+ |
| Network (NWPathMonitor) | 12.0 | 26.0 | Stable, unchanged API |
| CoreTelephony | 4.0 | 26.0 | CTCarrier deprecated 16.4, radio tech still works |
| CoreLocation | 2.0 | 26.0 | CLServiceSession requires 18+ |
| Swift Charts | 16.0 | 26.0 | 3D charts new in 26 (not needed) |
| BackgroundTasks | 13.0 | 26.0 | BGContinuedProcessingTask new in 26 |
## What NOT to Use
| Technology | Why Not |
|------------|---------|
| Combine | Maintenance mode. Use Swift Concurrency (async/await, actors) instead. |
| ObservableObject / @Published | Legacy pattern. Use @Observable (Observation framework) for iOS 17+. |
| Reachability.swift | Legacy wrapper around SCNetworkReachability. NWPathMonitor replaced this in iOS 12. |
| Alamofire | Massive overkill for a single HEAD request. URLSession is fine. |
| Firebase / Analytics | No cloud backend. All local. |
| Realm | Heavy external dependency for simple event logging. |
| CoreData (direct) | Use SwiftData instead for new projects targeting iOS 17+. |
| Continuous GPS (`requestAlwaysAuthorization` + `startUpdatingLocation`) | Battery killer. Significant location changes is the right approach. |
| `CLMonitor` for significant location | Crash bugs on recreation, 20-region limit, less mature than CLLocationManager. |
| Push Notifications for background wake | No server to send pushes from. Not applicable. |
| `Timer` / `DispatchSourceTimer` in background | iOS suspends timers when app is backgrounded. They do NOT fire reliably. Use the wake-then-probe pattern instead. |
## Sources
- [NWPathMonitor - Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [serviceCurrentRadioAccessTechnology - Apple Developer Documentation](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology)
- [CTCarrier Deprecation - Apple Developer Forums](https://developer.apple.com/forums/thread/714876)
- [CLServiceSession and Modern Core Location - twocentstudios.com](https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/)
- [startMonitoringSignificantLocationChanges - Apple Developer Documentation](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges())
- [Handling location updates in the background - Apple Developer Documentation](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [iOS 26 Background APIs: BGContinuedProcessingTask - DEV Community](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)
- [Key Considerations Before Using SwiftData - fatbobman.com](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [SwiftData Background Tasks - useyourloaf.com](https://useyourloaf.com/blog/swiftdata-background-tasks/)
- [Approachable Concurrency in Swift 6.2 - avanderlee.com](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [Swift Charts - Apple Developer Documentation](https://developer.apple.com/documentation/Charts)
- [ShareLink / fileExporter - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-export-files-using-fileexporter)
- [Configuring background execution modes - Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
