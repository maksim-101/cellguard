---
phase: 07-wifi-context
reviewed: 2026-04-20T20:22:03Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - CellGuard/CellGuard.entitlements
  - CellGuard/Models/ConnectivityEvent.swift
  - CellGuard/Services/ConnectivityMonitor.swift
  - CellGuard/Views/EventDetailView.swift
  - CellGuard/Views/DashboardView.swift
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-04-20T20:22:03Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Reviewed the core files related to Phase 7 (Wi-Fi SSID capture). The `wifiSSID` property is well-integrated into the model, entitlement is correctly configured, and the `NEHotspotNetwork.fetchCurrent()` call in `captureWifiSSID()` is properly async with graceful nil handling. The Wi-Fi section in EventDetailView conditionally renders only when SSID data exists.

Three warnings identified: (1) silently swallowed persistence errors in the core event logging path, (2) hardcoded `isExpensive`/`isConstrained` values producing inaccurate metadata on all probe events, and (3) an unstructured Task in `logEvent` that can silently lose events if the monitor is deallocated. Two info-level items for minor code hygiene.

## Warnings

### WR-01: Silent Error Suppression in Event Persistence

**File:** `CellGuard/Services/ConnectivityMonitor.swift:534`
**Issue:** `try? await eventStore.insertEvent(event)` silently discards SwiftData save failures. Since the app's core purpose is producing structured evidence of connectivity drops, silently losing events undermines the entire value proposition. A transient save failure (e.g., disk full, migration issue) would result in lost drop evidence with no indication to the user or logs.
**Fix:** At minimum, log the error. Ideally, surface persistent save failures to the UI or retry:
```swift
do {
    try await eventStore.insertEvent(event)
} catch {
    // At minimum: structured logging for debugging
    print("[CellGuard] Failed to persist event (\(type)): \(error)")
    // Consider: retry queue, or increment a health service counter
}
```

### WR-02: Hardcoded isExpensive/isConstrained in Probe Events

**File:** `CellGuard/Services/ConnectivityMonitor.swift:245-246`
**Issue:** All probe-originated events (lines 245, 255, 271, 285) hardcode `isExpensive: false` and `isConstrained: false` instead of capturing the actual NWPath flags. The `runProbe()` method correctly captures `currentPathStatus` and `currentInterfaceType` before the await (Pitfall 5), but the expensive/constrained flags are not exposed as observable properties and therefore cannot be captured at probe time. This means every probe event (probeSuccess, probeFailure, silentFailure) contains inaccurate network cost metadata.
**Fix:** Add observable properties for `isExpensive`/`isConstrained` alongside the existing `currentPathStatus`/`currentInterfaceType`, updating them in `handlePathUpdate`:
```swift
// Add to published state section:
private(set) var currentIsExpensive: Bool = false
private(set) var currentIsConstrained: Bool = false

// In handlePathUpdate, after updating currentPathStatus/currentInterfaceType:
currentIsExpensive = path.isExpensive
currentIsConstrained = path.isConstrained

// In runProbe, capture alongside other state:
let capturedExpensive = currentIsExpensive
let capturedConstrained = currentIsConstrained
```

### WR-03: Unstructured Task in logEvent Can Lose Events

**File:** `CellGuard/Services/ConnectivityMonitor.swift:514-535`
**Issue:** `logEvent` creates an unstructured `Task` to await `captureWifiSSID()` and persist the event. If the `ConnectivityMonitor` is deallocated (e.g., during app termination or a re-creation), the Task holds only a strong reference to `eventStore` (captured implicitly) but no guarantee of completion. Additionally, rapid event logging creates multiple concurrent Tasks that may execute out of order, causing events to be persisted with incorrect temporal ordering. While SwiftData sorts by timestamp (not insertion order), out-of-order persistence could cause issues with any sequential processing logic.
**Fix:** Consider using a serial `AsyncStream` or actor-based queue to ensure ordered, reliable persistence. At minimum, store the Task and await it during `stopMonitoring()`:
```swift
private var pendingPersistTasks: [Task<Void, Never>] = []

// In logEvent:
let task = Task { ... }
pendingPersistTasks.append(task)

// In stopMonitoring:
for task in pendingPersistTasks { await task.value }
pendingPersistTasks.removeAll()
```

## Info

### IN-01: Force-Unwrap Inside Nil Check

**File:** `CellGuard/Views/EventDetailView.swift:32`
**Issue:** `event.wifiSSID!` uses a force-unwrap inside an `if event.wifiSSID != nil` guard. While safe at runtime, force-unwraps are fragile under refactoring -- if the surrounding conditional is ever moved or restructured, it becomes a crash. Idiomatic Swift prefers `if let` binding.
**Fix:**
```swift
if let ssid = event.wifiSSID {
    Section("Wi-Fi") {
        LabeledContent("SSID", value: ssid.isEmpty ? "\u{2014}" : ssid)
    }
}
```

### IN-02: Initial Path State Update Suppresses isExpensive/isConstrained

**File:** `CellGuard/Services/ConnectivityMonitor.swift:369-376`
**Issue:** The initial path update handler captures `previousPathStatus` and `previousInterfaceType` but does not initialize `currentIsExpensive`/`currentIsConstrained` (once WR-02 is addressed). When the fix for WR-02 is applied, the initial update block should also set the cost flags:
```swift
if isInitialUpdate {
    previousPathStatus = newStatus
    previousInterfaceType = newInterface
    currentPathStatus = newStatus
    currentInterfaceType = newInterface
    currentIsExpensive = isExpensive
    currentIsConstrained = isConstrained
    isInitialUpdate = false
    return
}
```

---

_Reviewed: 2026-04-20T20:22:03Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
