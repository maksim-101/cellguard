# Phase 4: UI and Evidence Export - Research

**Researched:** 2026-03-25
**Domain:** SwiftUI dashboard, Swift Charts visualization, JSON export via ShareLink, local notifications
**Confidence:** HIGH

## Summary

Phase 4 transforms the existing raw event list (ContentView) into a proper dashboard with statistics, an event log browser, a timeline chart, JSON export, and a summary report. The existing codebase already has all the data infrastructure: ConnectivityEvent model with Codable conformance, EventStore actor with fetch/count methods, and @Query-driven views. The UI work is pure SwiftUI with no new frameworks except Swift Charts (already in the stack) and UNUserNotificationCenter (already used by ProvisioningProfileService).

The most important architectural insight is that the current ContentView already serves as both dashboard and event list -- this phase needs to split it into distinct views within a NavigationStack. The ConnectivityEvent model already conforms to Codable, so JSON export is essentially "fetch all, encode, write to temp file, share via ShareLink." The summary report is pure computation over the fetched event array.

**Primary recommendation:** Split ContentView into DashboardView (stats + chart), EventListView (scrollable log), and EventDetailView (single event metadata). Use ShareLink with a Transferable wrapper that writes JSON to a temp file. Add a drop notification hook in ConnectivityMonitor.logEvent().

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MON-07 | Local notification after drop detection prompting sysdiagnose | UNUserNotificationCenter already authorized by ProvisioningProfileService. Add notification scheduling in ConnectivityMonitor.logEvent() for drop event types. |
| UI-01 | Dashboard: monitoring status, connectivity state, drop counts (24h/7d/total), last drop | Existing health bar pattern + @Query with date predicates for counts. ConnectivityMonitor already exposes currentPathStatus, currentInterfaceType, isMonitoring. |
| UI-02 | Scrollable reverse-chronological event log | Existing @Query(sort: \.timestamp, order: .reverse) pattern in ContentView. Extract to dedicated EventListView. |
| UI-03 | Event detail view with full metadata | New EventDetailView displaying all ConnectivityEvent properties. NavigationLink from event list rows. |
| UI-04 | Launch directly to dashboard, no onboarding beyond permission prompts | Already the case -- CellGuardApp launches to ContentView with no onboarding. Permission prompts triggered lazily by startMonitoring(). Just ensure new DashboardView is the root. |
| EXP-01 | Export full event log as JSON via Share Sheet | ConnectivityEvent already Codable. Use ShareLink with Transferable FileRepresentation. Write JSONEncoder output to temp directory. |
| EXP-02 | Summary report: total drops, by type, avg/max duration, per day, location/radio distribution | Pure computation over [ConnectivityEvent] array. No new framework needed. |
| EXP-03 | Swift Charts timeline with silent failures visually distinct | Swift Charts BarMark with foregroundStyle based on event type. Group by day/hour. |
</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Charts | iOS 16+ (built-in) | Timeline visualization (EXP-03) | First-party. BarMark + foregroundStyle for drop type distinction. No external dependency. |
| ShareLink (SwiftUI) | iOS 16+ | Share JSON file via system share sheet (EXP-01) | Native SwiftUI. Works with Transferable protocol. |
| UNUserNotificationCenter | iOS 10+ | Local notification on drop detection (MON-07) | Already used by ProvisioningProfileService for profile expiry notification. |
| JSONEncoder (Foundation) | Built-in | Serialize events to JSON (EXP-01) | ConnectivityEvent already conforms to Codable with custom encode/decode. |
| NavigationStack (SwiftUI) | iOS 16+ | Dashboard -> Event List -> Detail navigation | Already used in ContentView. |
| @Query (SwiftData) | iOS 17+ | Live-updating event queries for dashboard counts | Already used in ContentView. |

### No New Dependencies Required

This phase uses exclusively first-party frameworks already in the project. No new packages, no new imports beyond `Charts`.

## Architecture Patterns

### Recommended View Structure
```
CellGuard/Views/
  ContentView.swift          # Root: NavigationStack with tab-like structure
  DashboardView.swift        # Stats cards, chart, quick actions (NEW)
  EventListView.swift        # Scrollable reverse-chronological event list (NEW)
  EventDetailView.swift      # Full metadata for single event (NEW)
  SummaryReportView.swift    # Generated summary report display (NEW)
  HealthDetailSheet.swift    # Existing -- no changes needed
  Components/
    DropCountCard.swift      # Reusable stat card (NEW)
```

### Pattern 1: Dashboard Stats via @Query with Date Predicates

**What:** Use multiple @Query properties with date-filtered predicates for 24h/7d/total counts.

**Important constraint:** @Query filter predicates must use captured constants, not Date.now directly inside #Predicate.

```swift
// Dashboard drop counts -- capture date constants outside predicate
struct DashboardView: View {
    // Total drops (pathChange where status went unsatisfied + silentFailure)
    @Query(filter: #Predicate<ConnectivityEvent> {
        $0.eventTypeRaw == 1 // silentFailure
    }, sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var silentFailures: [ConnectivityEvent]

    // For date-range filtering, use a computed approach or
    // filter the full @Query result in-memory (acceptable for ~10k events)
    @Query(sort: \ConnectivityEvent.timestamp, order: .reverse)
    private var allEvents: [ConnectivityEvent]

    private var drops24h: Int {
        let cutoff = Date.now.addingTimeInterval(-24 * 3600)
        return allEvents.filter { $0.timestamp >= cutoff && isDropEvent($0) }.count
    }
}
```

**Why in-memory filtering is acceptable:** At ~1,440 events/day, 7 days = ~10,000 events. Filtering 10k Swift objects is sub-millisecond. The @Query already fetches all events for the event list (UI-02), so reusing it for dashboard counts avoids duplicate fetches.

### Pattern 2: ShareLink with Transferable File Export

**What:** Create a Transferable wrapper that encodes all events to JSON and writes to a temp file.

```swift
struct EventLogExport: Transferable {
    let events: [ConnectivityEvent]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export.events)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cellguard-events.json")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// Usage in view:
ShareLink(
    item: EventLogExport(events: allEvents),
    preview: SharePreview("CellGuard Event Log", image: Image(systemName: "doc.text"))
)
```

### Pattern 3: Local Notification on Drop Detection

**What:** Fire a local notification immediately when a drop or silent failure is detected, prompting the user to capture a sysdiagnose.

```swift
// In ConnectivityMonitor.logEvent() or a new NotificationService
private func scheduleDropNotification(eventType: EventType) {
    guard eventType == .pathChange || eventType == .silentFailure else { return }

    let content = UNMutableNotificationContent()
    content.title = "Cellular Drop Detected"
    content.body = "Capture a sysdiagnose now: Settings > Privacy > Analytics > sysdiagnose"
    content.sound = .default

    // Fire immediately (1 second delay minimum for time interval trigger)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
        identifier: "dropAlert-\(UUID().uuidString)",
        content: content,
        trigger: trigger
    )
    UNUserNotificationCenter.current().add(request)
}
```

**Key detail:** Use a unique identifier per notification (UUID suffix) so multiple drops don't replace each other. The notification fires even when the app is in the background as long as the process is alive.

### Pattern 4: Swift Charts Timeline

**What:** BarMark chart showing drops over time with silent failures visually distinct.

```swift
import Charts

struct DropTimelineChart: View {
    let events: [ConnectivityEvent]

    private var dropEvents: [ConnectivityEvent] {
        events.filter { $0.eventType == .silentFailure || $0.eventType == .pathChange }
    }

    var body: some View {
        Chart(dropEvents) { event in
            BarMark(
                x: .value("Time", event.timestamp, unit: .hour),
                y: .value("Drops", 1)
            )
            .foregroundStyle(by: .value("Type", event.eventType == .silentFailure ? "Silent" : "Overt"))
        }
        .chartForegroundStyleScale([
            "Silent": .red,
            "Overt": .orange
        ])
    }
}
```

### Anti-Patterns to Avoid
- **Separate @Query per time range for counts:** Creates multiple SwiftData fetches. Better to fetch once and filter in memory at this data volume.
- **UIActivityViewController bridging:** Use ShareLink, not UIKit wrappers.
- **Background URLSession for export:** Unnecessary. Export is fast enough synchronously for weeks of data (~10k events). Only consider BGContinuedProcessingTask if export demonstrably takes >5s.
- **NavigationLink with value-based navigation for simple detail:** For a 3-level hierarchy (dashboard -> list -> detail), direct NavigationLink with destination closure is simpler than NavigationPath-based routing.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File sharing UI | Custom share sheet | ShareLink + Transferable | System share sheet handles all destinations (Files, AirDrop, Messages, etc.) |
| JSON serialization | Manual string building | JSONEncoder + Codable | ConnectivityEvent already has full Codable conformance with custom coding keys |
| Chart rendering | Custom drawing | Swift Charts BarMark | Handles axes, scaling, legends, accessibility automatically |
| Date grouping for chart | Manual Calendar math | BarMark(x: .value("Time", date, unit: .hour)) | Swift Charts handles temporal binning natively |
| Notification scheduling | Custom timer-based alerts | UNUserNotificationCenter | Works in background, survives app suspension, handles permissions |

## Common Pitfalls

### Pitfall 1: @Query Does Not Support Date.now in Predicate
**What goes wrong:** Using `Date.now` or `Date()` directly inside `#Predicate` causes a compile error.
**Why it happens:** #Predicate macros capture only stored properties and local constants, not dynamic expressions.
**How to avoid:** Either capture the date as a local `let` before the predicate, or filter the @Query results in memory (recommended for this data volume).
**Warning signs:** Compile error inside #Predicate block.

### Pitfall 2: ShareLink Transferable FileRepresentation Creates File Synchronously
**What goes wrong:** If encoding thousands of events to JSON takes time, the UI thread freezes when the share sheet opens.
**Why it happens:** FileRepresentation's exporting closure runs synchronously on the calling thread.
**How to avoid:** For ~10k events, JSONEncoder is fast enough (<100ms). If weeks of data grows larger, pre-generate the file asynchronously and share the URL directly.
**Warning signs:** Share sheet takes >1s to appear.

### Pitfall 3: Notification Permission Not Yet Granted
**What goes wrong:** Drop notifications silently fail to deliver.
**Why it happens:** UNUserNotificationCenter.requestAuthorization() may not have been called before the first drop.
**How to avoid:** ProvisioningProfileService already requests notification authorization in scheduleExpiryNotification(). Ensure this runs before the first drop could occur (it does -- loadProfile() is called in onAppear). Additionally, request authorization explicitly when monitoring starts.
**Warning signs:** No notification appears after a detected drop.

### Pitfall 4: SwiftData @Query Refresh Bug (Already Handled)
**What goes wrong:** Dashboard counts don't update after background writes.
**Why it happens:** iOS 18+ @Query doesn't refresh after @ModelActor background inserts.
**How to avoid:** Already handled in ContentView via `modelContext.processPendingChanges()` on scenePhase .active. Ensure new DashboardView inherits this pattern.
**Warning signs:** Stale counts after returning from background.

### Pitfall 5: Event Type Classification for "Drops"
**What goes wrong:** Dashboard counts drops incorrectly because the definition of "a drop" spans multiple event types.
**Why it happens:** A "drop" could be: pathChange with status going unsatisfied, silentFailure, or probeFailure. Not all pathChange events are drops (Wi-Fi fallback is a pathChange too).
**How to avoid:** Define a clear `isDropEvent` helper: silentFailure events are always drops; pathChange events are drops only when pathStatus is .unsatisfied or .requiresConnection. probeFailure is NOT a drop (could be transient). connectivityRestored is NOT a drop.
**Warning signs:** Drop counts don't match user expectations.

## Code Examples

### Summary Report Computation (EXP-02)

```swift
struct SummaryReport {
    let totalDrops: Int
    let overtDrops: Int
    let silentDrops: Int
    let averageDurationSeconds: Double?
    let maxDurationSeconds: Double?
    let dropsPerDay: Double
    let radioDistribution: [(radio: String, count: Int)]
    let locationClusters: Int  // Distinct ~1km grid cells with drops

    static func generate(from events: [ConnectivityEvent]) -> SummaryReport {
        let drops = events.filter { isDropEvent($0) }
        let silent = drops.filter { $0.eventType == .silentFailure }
        let overt = drops.filter { $0.eventType != .silentFailure }

        let durations = drops.compactMap(\.dropDurationSeconds)
        let avgDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max()

        // Days spanned
        let dateRange = events.compactMap(\.timestamp).sorted()
        let daySpan = max(1, Calendar.current.dateComponents([.day],
            from: dateRange.first ?? Date(),
            to: dateRange.last ?? Date()).day ?? 1)
        let dropsPerDay = Double(drops.count) / Double(daySpan)

        // Radio tech distribution
        let radioGroups = Dictionary(grouping: drops) {
            $0.radioTechnology?.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") ?? "Unknown"
        }
        let radioDistribution = radioGroups.map { (radio: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        return SummaryReport(
            totalDrops: drops.count,
            overtDrops: overt.count,
            silentDrops: silent.count,
            averageDurationSeconds: avgDuration,
            maxDurationSeconds: maxDuration,
            dropsPerDay: dropsPerDay,
            radioDistribution: radioDistribution,
            locationClusters: countLocationClusters(drops)
        )
    }
}
```

### Drop Event Classification Helper

```swift
/// Determines if a ConnectivityEvent represents a connectivity drop.
/// Used for dashboard counts, summary reports, and chart filtering.
func isDropEvent(_ event: ConnectivityEvent) -> Bool {
    switch event.eventType {
    case .silentFailure:
        return true
    case .pathChange:
        // Only count path changes where connectivity was lost
        return event.pathStatus == .unsatisfied || event.pathStatus == .requiresConnection
    default:
        return false
    }
}
```

### EventDetailView Layout

```swift
struct EventDetailView: View {
    let event: ConnectivityEvent

    var body: some View {
        List {
            Section("Event") {
                LabeledContent("Type", value: event.eventType.displayName)
                LabeledContent("Time", value: event.timestamp.formatted(.dateTime))
            }
            Section("Network") {
                LabeledContent("Path Status", value: "\(event.pathStatus)")
                LabeledContent("Interface", value: "\(event.interfaceType)")
                LabeledContent("Expensive", value: event.isExpensive ? "Yes" : "No")
                LabeledContent("Constrained", value: event.isConstrained ? "Yes" : "No")
            }
            Section("Cellular") {
                LabeledContent("Radio Tech", value: event.radioTechnology ?? "Unknown")
                LabeledContent("Carrier", value: event.carrierName ?? "Unknown")
            }
            if event.probeLatencyMs != nil || event.probeFailureReason != nil {
                Section("Probe") {
                    if let latency = event.probeLatencyMs {
                        LabeledContent("Latency", value: String(format: "%.0f ms", latency))
                    }
                    if let reason = event.probeFailureReason {
                        LabeledContent("Failure", value: reason)
                    }
                }
            }
            if event.latitude != nil {
                Section("Location") {
                    LabeledContent("Latitude", value: String(format: "%.4f", event.latitude ?? 0))
                    LabeledContent("Longitude", value: String(format: "%.4f", event.longitude ?? 0))
                    LabeledContent("Accuracy", value: String(format: "%.0f m", event.locationAccuracy ?? 0))
                }
            }
            if let duration = event.dropDurationSeconds {
                Section("Duration") {
                    LabeledContent("Drop Duration", value: formatDuration(duration))
                }
            }
        }
        .navigationTitle(event.eventType.displayName)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| UIActivityViewController | ShareLink + Transferable | iOS 16 (2022) | No UIKit bridge needed in SwiftUI |
| ObservableObject + @Published | @Observable (Observation) | iOS 17 (2023) | Already used in project |
| Custom chart drawing | Swift Charts | iOS 16 (2022) | Declarative charting with automatic accessibility |
| NSPredicate (Core Data) | #Predicate macro (SwiftData) | iOS 17 (2023) | Type-safe, Swift-native predicates |

## Open Questions

1. **Drop event type classification across phases**
   - What we know: silentFailure is always a drop. pathChange to unsatisfied is a drop. Wi-Fi fallback (pathChange but still satisfied) is NOT a drop.
   - What's unclear: Should probeFailure count as a "drop" in dashboard counts? Current classification says no (could be transient server issue).
   - Recommendation: Exclude probeFailure from drop counts. Only silentFailure and pathChange-to-unsatisfied are drops.

2. **Summary report "location distribution" granularity**
   - What we know: Events have latitude/longitude with ~500m accuracy (cell tower level).
   - What's unclear: How to meaningfully cluster locations -- grid cells? Named areas?
   - Recommendation: Use ~1km grid cells (round to 2 decimal places) and count unique cells. Simple and accurate enough for "this tends to happen in area X."

3. **Notification authorization timing**
   - What we know: ProvisioningProfileService.loadProfile() requests authorization on first launch.
   - What's unclear: If the user denies notification permission, should we show a UI prompt?
   - Recommendation: No special UI -- the notification is supplementary. If denied, drops are still logged. The sysdiagnose prompt is a convenience, not critical functionality.

## Sources

### Primary (HIGH confidence)
- Existing codebase: ConnectivityEvent.swift (full Codable conformance), EventStore.swift (fetch/count methods), ContentView.swift (existing @Query + health bar pattern)
- [ShareLink - Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/ShareLink)
- [UNUserNotificationCenter - Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Swift Charts - Apple Developer Documentation](https://developer.apple.com/documentation/Charts)

### Secondary (MEDIUM confidence)
- [Sharing content in SwiftUI - Swift with Majid](https://swiftwithmajid.com/2023/03/28/sharing-content-in-swiftui/) - FileRepresentation pattern verified
- [Sharing files in SwiftUI - Sima's Swifty Blog](https://www.simanerush.com/posts/sharing-files) - SentTransferredFile usage
- [SwiftData predicates - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-filter-swiftdata-results-with-predicates) - Date filtering limitations
- [Mastering charts in SwiftUI - Swift with Majid](https://swiftwithmajid.com/2023/01/10/mastering-charts-in-swiftui-basics/) - BarMark temporal binning

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All first-party frameworks already in project or well-documented
- Architecture: HIGH - View decomposition follows standard SwiftUI NavigationStack patterns; existing codebase patterns are clear
- Pitfalls: HIGH - Known SwiftData @Query limitations already handled in codebase; ShareLink/Transferable patterns well-documented
- Export: HIGH - ConnectivityEvent already has complete Codable conformance; JSONEncoder is trivial
- Notifications: HIGH - UNUserNotificationCenter already used in project; pattern is straightforward

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable first-party APIs, no fast-moving dependencies)
