# Project Brief

## CellGuard — iOS Cellular Connectivity Drop Logger

| | |
|---|---|
| **Author** | Maksim |
| **Date** | 25 March 2026 |
| **Target Platform** | iOS 26.x / iPhone 17 Pro Max |
| **Development Tool** | Claude Code |
| **Status** | Draft |

---

## 1. Problem Statement

Since purchasing an iPhone 17 Pro Max running iOS 26, the device exhibits persistent, sporadic cellular connectivity drops. These manifest as interrupted phone calls, failure to load app content, and silent loss of network reachability — where the device appears registered on the network but is effectively unreachable (callers hear normal ringing, SMS show as delivered, but nothing reaches the device).

The issue persists across a full device replacement by Apple, across multiple iOS versions (26.0 through 26.4), and is not resolved by switching to LTE-only mode, manually selecting the carrier (Swisscom), resetting network settings, or updating carrier bundles. The current modem firmware is 1.55.04 (Swisscom 69.0). This pattern is consistent with a documented baseband modem state-machine failure affecting the iPhone 17 series, widely reported on MacRumors, Apple Community forums, and tech press.

The only user-side recovery is toggling Airplane Mode, which forces a baseband re-registration. This is not possible during active phone calls, meaning calls are irrecoverably lost when the modem enters this state.

---

## 2. Objective

Build a lightweight iOS app that continuously monitors cellular network connectivity in the background and logs every detected drop with contextual metadata. The primary purpose is to produce a structured, timestamped evidence log that can be attached to an Apple Feedback Assistant report, giving Apple's engineering team precise data on the frequency, timing, duration, and conditions of these connectivity failures.

**Secondary objectives:**

- Identify patterns (time of day, location, network type, Wi-Fi handover correlation) that may help narrow the root cause.
- Provide a personal dashboard of drop frequency and trends.
- Serve as a reusable diagnostic tool for anyone experiencing similar modem issues on iPhone 17 series devices.

---

## 3. Why a Native App (Not Shortcuts)

iOS Shortcuts cannot fulfil this requirement. Shortcuts lacks a time-based trigger at sub-hourly intervals, cannot run persistent background loops (iOS terminates long-running shortcuts), and cannot programmatically toggle Airplane Mode. The cellular data exposed to Shortcuts via "Get Network Details" is also limited to carrier name, radio technology, and country code — no signal strength, no connection state transitions, and no modem status.

A native iOS app, by contrast, has access to Apple's Network framework, specifically ***NWPathMonitor***, which provides real-time callbacks whenever the device's network path changes state (e.g., from "satisfied" to "unsatisfied", or when the interface type changes between cellular and Wi-Fi). This is the correct tool for the job: it fires at the moment of state change rather than polling, and it operates in the background with proper iOS background execution entitlements.

---

## 4. Technical Approach

### 4.1 Core Monitoring Engine

The app's central component is an NWPathMonitor instance that observes changes to the device's network path. On each state transition, the app captures a snapshot including the transition type, timestamp, available interfaces (cellular, Wi-Fi, wired), whether the path is "satisfied" (connectivity available) or "unsatisfied", whether the path is "constrained" (e.g., Low Data Mode), and whether the connection is "expensive" (cellular).

Additionally, a periodic health check (e.g., every 60 seconds) should attempt a lightweight connectivity test (such as a HEAD request to a reliable endpoint) to detect the specific "attached but unreachable" modem state where NWPathMonitor may still report the path as "satisfied" because the modem believes it is connected, even though no data can actually transit. This is the most insidious variant of the bug.

### 4.2 Data Captured Per Event

| Field | Description |
|---|---|
| **Timestamp** | ISO 8601, device local time and UTC |
| **Event Type** | path_change, connectivity_check_fail, connectivity_restored |
| **Path Status** | satisfied / unsatisfied / requiresConnection |
| **Interface Type** | cellular, wifi, wiredEthernet, loopback, other |
| **Is Expensive** | Boolean — indicates cellular |
| **Is Constrained** | Boolean — indicates Low Data Mode or similar |
| **Radio Technology** | If obtainable via CTTelephonyNetworkInfo: LTE, NR (5G), etc. |
| **Carrier Name** | Via CTTelephonyNetworkInfo |
| **Location** | Coarse location (if permitted) for geographic pattern analysis |
| **Wi-Fi SSID** | If connected to Wi-Fi at time of event (requires entitlement) |
| **Connectivity Test** | Result of HEAD request (latency in ms, or failure reason) |
| **Duration of Drop** | Calculated from drop event to next restoration event |

### 4.3 Background Execution

For the app to be useful, it must run in the background. iOS is restrictive about background execution, but several legitimate entitlements apply here. The app should use Background App Refresh for periodic connectivity checks, and NWPathMonitor itself can be configured to deliver updates while the app is backgrounded. The app should also consider registering as a location-aware app (using significant location changes, not continuous GPS) to maintain background execution eligibility while also capturing coarse location data for pattern analysis. The exact background strategy should be determined during development based on what iOS 26 permits without excessive battery drain.

### 4.4 Local Storage and Export

All data is stored locally on-device. No cloud backend, no external data transmission. Storage should use a lightweight local database (e.g., SwiftData or a simple SQLite/JSON store) that can hold weeks of event data without significant storage impact. The app must support exporting the log as a structured file (CSV or JSON) suitable for attaching to a Feedback Assistant report. Optionally, the app could also generate a summary report (number of drops per day, average duration, most affected times/locations).

### 4.5 User Interface

The UI should be minimal. A dashboard showing current connectivity status, a count of drops in the last 24 hours / 7 days, and a scrollable log of recent events. A detail view for each event showing all captured metadata. An export button that generates the CSV/JSON file and presents the iOS share sheet. No onboarding flow beyond the necessary permission requests (location, network access).

---

## 5. Scope and Constraints

### 5.1 In Scope

- Real-time monitoring of network path changes via NWPathMonitor.
- Periodic active connectivity checks (HEAD request) to detect silent modem failures.
- Structured local logging of all connectivity events with metadata.
- CSV/JSON export for Feedback Assistant attachment.
- Minimal dashboard UI with drop count and event log.
- Background execution with reasonable battery impact.

### 5.2 Out of Scope

- Any attempt to programmatically recover from drops (toggling Airplane Mode is not accessible to third-party apps).
- Cloud storage, analytics backend, or data transmission of any kind.
- Signal strength (dBm/RSSI) monitoring — Apple does not expose this to third-party apps.
- Direct modem/baseband state access — this is a private framework not available to App Store or sideloaded apps.
- App Store distribution — this is a personal diagnostic tool deployed via Xcode to the developer's own device.

---

## 6. Deployment

The app will be deployed directly to the developer's iPhone 17 Pro Max via Xcode (personal team signing). No App Store submission is planned. The app must be re-signed every 7 days with a free Apple Developer account, or can run indefinitely if deployed with a paid Apple Developer Program membership. Development will be done using Claude Code, with the project structured as a standard SwiftUI app targeting iOS 26.

---

## 7. Success Criteria

1. The app reliably detects and logs connectivity drops that the user can corroborate with their experience (e.g., a dropped call at a logged timestamp).
2. The app detects the "attached but unreachable" modem state via periodic connectivity checks, even when NWPathMonitor reports "satisfied."
3. The app runs in the background for at least 24 hours without being terminated by iOS or causing noticeable battery drain.
4. The exported log is structured, complete, and immediately usable as an attachment to a Feedback Assistant report.
5. After two weeks of logging, the data reveals actionable patterns (frequency, timing, location, conditions) that strengthen the case for an Apple engineering investigation.
