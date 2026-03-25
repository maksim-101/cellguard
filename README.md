# CellGuard

A lightweight iOS diagnostic app that continuously monitors cellular connectivity in the background and logs every detected drop with contextual metadata. Built to produce structured, timestamped evidence for an Apple Feedback Assistant report documenting persistent baseband modem failures on the iPhone 17 Pro Max.

## Why This Exists

The iPhone 17 Pro Max has a widely reported cellular connectivity bug where the baseband modem enters a failed state — sometimes silently, where the device appears connected but no data transits. The only recovery is toggling Airplane Mode, and active calls are irrecoverably lost. This app creates the evidence trail Apple engineering needs to investigate.

## What It Does

- **Real-time monitoring** — NWPathMonitor tracks every network path change (cellular drop, Wi-Fi fallback, restoration)
- **Silent failure detection** — HEAD requests to Apple's captive portal every 60 seconds catch "attached but unreachable" modem states that NWPathMonitor misses
- **Background execution** — Runs 24/7 using significant location changes + Background App Refresh, survives app kills and reboots
- **Drop notifications** — Local notification on every detected drop, prompting immediate sysdiagnose capture
- **Full metadata** — Each event captures: timestamp, event type, path status, interface type, radio technology, carrier, probe result, GPS coordinates, drop duration
- **Gap detection** — Logs periods when iOS suspended monitoring so exported data accurately represents coverage
- **Dashboard** — Health status bar, drop counts (24h/7d/total), connectivity state, Swift Charts timeline
- **JSON export** — One-tap export of the complete event log via the iOS Share Sheet for Feedback Assistant attachment
- **Summary report** — Drops per day, duration statistics, radio technology breakdown, location distribution

## Requirements

- **Xcode 26** (Swift 6.2, iOS 26 SDK)
- **iPhone running iOS 26.x** (built for iPhone 17 Pro Max but runs on any iOS 26 device)
- **Apple ID** (free personal team signing — no paid developer program required)
- **macOS** with Xcode installed

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/maksim-101/cellguard.git
cd cellguard
```

### 2. Open in Xcode

```bash
open CellGuard.xcodeproj
```

### 3. Configure signing

1. Select the **CellGuard** target in the project navigator
2. Go to the **Signing & Capabilities** tab
3. Set **Team** to your Personal Team (your Apple ID)
4. Change the **Bundle Identifier** to something unique (e.g., `com.yourname.CellGuard`)

### 4. Connect your iPhone

Connect via USB cable, or use wireless debugging if already paired. Select your iPhone as the run destination in Xcode's toolbar.

### 5. Trust the developer profile (first time only)

On your iPhone:
1. Go to **Settings > General > VPN & Device Management**
2. Tap your Apple ID under "Developer App"
3. Tap **Trust**

### 6. Build and run

Press **Cmd+R** in Xcode. The app will build, install, and launch on your device.

### 7. Grant permissions

On first launch, the app will request:
- **Location** — select **"Always Allow"** (required for background monitoring via significant location changes)
- **Notifications** — allow (required for drop alerts)

### Important Notes

- **7-day re-signing** — Free personal team signing expires after 7 days. Simply re-run from Xcode (Cmd+R) to re-sign.
- **Don't force-quit** — The app must remain in the app switcher (not force-quit) for background monitoring to work. iOS wakes it automatically via significant location changes.
- **Background App Refresh** — Make sure this is enabled in Settings > General > Background App Refresh for CellGuard.
- **Low Power Mode** — Reduces background execution frequency. The app's health indicator will show "degraded" when active.

## Project Structure

```
CellGuard/
├── CellGuardApp.swift              # App entry point
├── App/
│   └── AppDelegate.swift           # UIKit lifecycle for background launch
├── Models/
│   ├── ConnectivityEvent.swift     # SwiftData model — all event metadata
│   ├── EventLogExport.swift        # Transferable model for JSON export
│   └── SummaryReport.swift         # Statistics computation
├── Services/
│   ├── ConnectivityMonitor.swift   # NWPathMonitor + HEAD probe coordinator
│   ├── EventStore.swift            # SwiftData @ModelActor for background writes
│   ├── LocationService.swift       # CLLocationManager + CLServiceSession
│   ├── MonitoringHealthService.swift   # Health state aggregation
│   └── ProvisioningProfileService.swift # Signing expiry detection
├── Views/
│   ├── ContentView.swift           # NavigationStack shell
│   ├── DashboardView.swift         # Main dashboard with health bar and stats
│   ├── EventListView.swift         # Reverse-chronological event log
│   ├── EventDetailView.swift       # Full event metadata detail
│   ├── DropTimelineChart.swift     # Swift Charts drop frequency visualization
│   ├── SummaryReportView.swift     # Evidence summary display
│   └── HealthDetailSheet.swift     # Monitoring health breakdown
├── Helpers/
│   └── DropClassification.swift    # Shared isDropEvent() classifier
└── Info.plist
```

## How It Works

**Detection pipeline:**

1. `NWPathMonitor` fires on every network path change (cellular drop, Wi-Fi fallback, restoration)
2. A HEAD request to `captive.apple.com/hotspot-detect.html` runs every 60 seconds to catch silent modem failures where NWPathMonitor still reports "satisfied"
3. Each event is classified (overt drop, silent failure, restoration, Wi-Fi fallback, etc.) and written to SwiftData via a background `@ModelActor`
4. Drop duration is computed from the time between a drop event and the next restoration

**Background strategy:**

- Significant location changes (~500m cell tower movement) wake the app indefinitely — even after iOS kills it or the device reboots
- Background App Refresh provides supplemental wake opportunities
- `CLServiceSession` (iOS 18+) ensures location delivery isn't silently dropped
- Monitoring gaps (when iOS suspends the app) are detected and logged so exported data shows true coverage

## Exporting Evidence

1. Open the app and tap **"Export Event Log (JSON)"** on the dashboard
2. The iOS Share Sheet opens with a timestamped JSON file
3. Save to Files, AirDrop to your Mac, or attach directly to a Feedback Assistant report

The **Summary Report** (accessible from the dashboard) provides a human-readable overview suitable for pasting into a bug report narrative.

## Privacy

All data stays on your device. There is no network communication except the HEAD request to Apple's captive portal for connectivity testing. No analytics, no cloud storage, no external data transmission of any kind.

## License

Personal diagnostic tool. No license specified.

## Built With

- Swift 6.2 / SwiftUI / iOS 26 SDK
- SwiftData for local persistence
- Network framework (NWPathMonitor)
- CoreTelephony for radio technology metadata
- CoreLocation for background execution + geographic context
- Swift Charts for timeline visualization
- [Claude Code](https://github.com/anthropics/claude-code) with [GSD workflow](https://github.com/gsd-build/get-shit-done)
