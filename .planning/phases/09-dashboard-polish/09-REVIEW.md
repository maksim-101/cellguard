---
phase: 09-dashboard-polish
type: code-review
status: issues
depth: standard
reviewed: 2026-04-25
files_reviewed: 4
findings:
  blocker: 0
  critical: 0
  major: 0
  minor: 4
  nit: 6
---

# Phase 9 Code Review — Dashboard Polish

**Reviewed:** 2026-04-25
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues (minor only — no blockers/criticals)

## Summary

Phase 9 is a tight, well-executed polish pass. All four files implement exactly what the SUMMARY documents claim, with sensible decision rationale embedded as comments. No security issues, no concurrency hazards, no retain-cycle risk.

A handful of minor issues are worth noting before the next phase, none of which block ship:
- Two stringly-typed coupling points (the UserDefaults key and the `"Silent"`/`"Overt"` discriminator) where a typo would be silently undetectable.
- Some now-dead helper code in `ConnectivityMonitor` (`captureRadioTechnology`, `captureCarrierName`) — pre-existing, not introduced here, but visible in the reviewed file.
- A redundant `_ = detectorNow` no-op statement in `handlePathUpdate` (pre-existing).
- One axis-closure cosmetic clean-up that the plan flagged as MAY-do and was intentionally skipped.

The dedup guard (Plan 09-01) is correctly designed — concurrent-callee blocking via START-clock-before-await, success-only suppression preserving every failure datum (D-14). The TimelineView wrapper (Plan 09-02) uses the right SwiftUI primitive and avoids Combine/Timer lifecycle headaches. The legend chips (Plan 09-03) correctly call `.chartLegend(.hidden)` to suppress the implicit Charts auto-legend.

---

## Findings

### Minor

**MN-01 — Duplicated UserDefaults key string (typo-fragile coupling)**
**Files:**
- `CellGuard/Services/LocationService.swift:55`
- `CellGuard/Views/HealthDetailSheet.swift:191`

`LocationService` writes via `DefaultsKey.lastBackgroundWakeTimestamp` (typed enum constant), but `HealthDetailSheet` reads the raw literal string `"lastBackgroundWakeTimestamp"`. The two strings are correct today, but a typo on either side is a silent runtime bug — the row would just permanently say "Never (no background wake yet)" with no compile error.

**Fix:** Promote the key to a shared constant (e.g., a top-level `enum AppDefaultsKeys` or extension on `UserDefaults` with a typed accessor) referenced from both files. Same applies to `"chartShowSilent"`/`"chartShowOvert"` if the dashboard ever needs to read them.

```swift
enum AppDefaultsKeys {
    static let lastBackgroundWakeTimestamp = "lastBackgroundWakeTimestamp"
}
```

**MN-02 — Stringly-typed bucket discriminator (`"Silent"` / `"Overt"`)**
**File:** `CellGuard/Views/DropTimelineChart.swift:107, 124-131, 200-203, 254, 257`

`TimeBucket.type` is a `String` set at line 107 (`event.eventType == .silentFailure ? "Silent" : "Overt"`) and matched by literal in three other places: the `visibleBuckets` switch (lines 126-129), the `chartForegroundStyleScale` keys (lines 201-202), and the chip labels (lines 254, 257). A typo in any one of these silently breaks color matching or filtering. Note that the popover legend definitions (lines 314, 323) are already a fifth copy.

**Fix:** Introduce a small `enum DropSeries: String { case silent = "Silent", overt = "Overt" }` and use `.silent.rawValue` / `.overt.rawValue` everywhere. `TimeBucket.type` becomes `DropSeries`. ~10-minute refactor.

**MN-03 — `MainActor` isolation of `locationManager(_:didUpdateLocations:)` is implicit, not annotated**
**File:** `CellGuard/Services/LocationService.swift:105-139`

The CLLocationManager delegate callback is invoked on the thread the manager was created on (main, since `LocationService` is constructed from `@MainActor` context), but the method itself isn't `@MainActor`-annotated. The body relies on this implicit isolation — particularly the `UIApplication.shared.applicationState` read inside the spawned `Task { @MainActor in ... }`. The Task block correctly hops onto MainActor, so `applicationState` is safely accessed. No actual bug, but the file mixes:

- `startMonitoring` / `stopMonitoring` — `@MainActor`-annotated.
- `locationManager(_:didUpdateLocations:)` — not annotated.
- `locationManagerDidChangeAuthorization` — not annotated, mutates `authorizationStatus`.

Under Swift 6 strict concurrency this may eventually warn. Worth annotating both delegate methods `@MainActor` (or marking the whole class `@MainActor`) for clarity and future-proofing.

**Fix:** Either annotate both delegate methods `@MainActor` or annotate the class itself.

**MN-04 — Nondeterministic ordering inside `buckets` could produce flicker on chip toggle**
**File:** `CellGuard/Views/DropTimelineChart.swift:111-117`

The inner loops over `grouped` (a `[Date: [String: Int]]`) iterate in dictionary order, which is unstable across runs. Sorting at line 117 only orders by `bucketStart`; within the same `bucketStart`, "Silent" and "Overt" can swap. With `BarMark`-stacked-by-type, this affects which color is on the bottom of the stack — visually subtle, but tapping a chip can re-render with the bottom layer color changed.

**Fix:**
```swift
return result.sorted { lhs, rhs in
    if lhs.bucketStart != rhs.bucketStart { return lhs.bucketStart < rhs.bucketStart }
    return lhs.type < rhs.type   // deterministic Silent-before-Overt
}
```

### Nit

**NT-01 — Redundant `_ = detectorNow` in `handlePathUpdate`**
**File:** `CellGuard/Services/ConnectivityMonitor.swift:557`

`let detectorNow = captureVPNDetectorBool()` at line 547 is used at line 548 to seed `vpnReassertingUntil`, then the value is intentionally discarded with `_ = detectorNow` at line 557. The `_ = detectorNow` line does nothing — the binding is already in scope. Pre-existing (Phase 8), not Phase 9, but visible in the reviewed file.

**Fix:** Delete line 557.

**NT-02 — Dead helper `captureRadioTechnology()` and stub `captureCarrierName()`**
**File:** `CellGuard/Services/ConnectivityMonitor.swift:423-432`

`captureCarrierName()` is a permanent `nil`-returning stub (lines 430-432) used in `logEvent`. Apple deprecated `CTCarrier`. Consider removing the stub and inlining `nil`, or documenting why the indirection exists. Pre-existing, not Phase 9.

**NT-03 — Axis closure unused-parameter cleanup not applied (intentional)**
**File:** `CellGuard/Views/DropTimelineChart.swift:215, 220, 225, 232`

`AxisMarks(...) { value in ... }` never references `value`. Plan flagged as MAY-do, executor intentionally skipped. Xcode 26 will likely emit "unused closure parameter" warnings on each of the four sites.

**Fix:** Replace `value in` with `_ in` at lines 215, 220, 225, 232.

**NT-04 — `lastWakeText` deletion and `lastActiveTimestamp` reader confirmation**
**File:** `CellGuard/Views/HealthDetailSheet.swift`

Confirmed `lastActiveTimestamp` no longer appears in this file; `lastWakeText` is fully deleted; old key not referenced. SUMMARY claim verified. No action needed — listing for completeness of the verification chain.

**NT-05 — TimelineView ticks once per second even when value is "Never"**
**File:** `CellGuard/Views/HealthDetailSheet.swift:110-119`

When the user has never had a background wake, the TimelineView fires the closure every second and recomputes `lastBackgroundWakeText`, getting the same `"Never (no background wake yet)"` string. SwiftUI short-circuits the redraw, but the closure body still runs once per second on the main thread, repeatedly hitting `UserDefaults.standard.double(forKey:)`. Negligible cost. Optional optimization: gate the ticker behind `if hasEverBackgroundWoken` and show a static row otherwise.

**NT-06 — `Spacer(minLength: 0)` at end of `legendBar` is fine**
**File:** `CellGuard/Views/DropTimelineChart.swift:274`

Behavior is correct — chips and (i) cluster left, blank space on the right (standard Apple Health pattern). No action.

---

## Cross-Reference Verification

| Claim from SUMMARY | Verified in code |
|---|---|
| `lastProbeStartedAt` set BEFORE await | YES — line 288, before `await probeSession.data(...)` on line 302 |
| Failures (`.probeFailure`, `.silentFailure`) never trigger early return | YES — guard checks `lastProbeOutcome == .probeSuccess` only |
| Outcome assigned at exactly 4 sites | YES — `.probeSuccess` ×1, `.probeFailure` ×2, `.silentFailure` ×1 |
| `import UIKit` in LocationService | YES — line 4 |
| `applicationState != .active` gate | YES — line 132 |
| `lastActiveTimestamp` write semantics unchanged | YES — lines 90, 123-126, 159-162 unaltered |
| `detectAndLogGap` reads `lastActiveTimestamp`, not new key | YES — line 155 |
| TimelineView wraps wake row | YES — lines 110-119 |
| `Date.RelativeFormatStyle` `.named` `.abbreviated` | YES — lines 194-195 |
| Empty-state copy `"Never (no background wake yet)"` | YES — line 192 |
| `Chart(visibleBuckets)` | YES — line 193 |
| `.chartLegend(.hidden)` present | YES — line 209 |
| Both-off hint exact copy | YES — line 187 |
| Default both chips ON | YES — lines 18, 22 (default `true`) |

---

## Concurrency / Threading

- `ConnectivityMonitor.runProbe` is `@MainActor` — `lastProbeStartedAt` and `lastProbeOutcome` are MainActor-isolated state. Concurrent callers (timer + location wake) both hop to MainActor before reading/writing, so the dedup guard is race-free. **PASS.**
- `LocationService.locationManager(_:didUpdateLocations:)` schedules its work in `Task { @MainActor in ... }`, so `UIApplication.shared.applicationState` read at line 132 is on the main thread. **PASS.** (See MN-03 for annotation suggestion.)
- `TimelineView` closure runs on the main run loop; `UserDefaults` reads are main-thread-safe. **PASS.**
- No retain cycles introduced. **PASS.**

---

## Security / Privacy

No new network endpoints, no new file I/O, no new entitlements. `lastBackgroundWakeTimestamp` is a Double in `UserDefaults` — local-only, no PII beyond a wake timestamp. Aligns with PROJECT.md "no external data transmission whatsoever." **PASS.**

---

_Reviewed: 2026-04-25_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Files: ConnectivityMonitor.swift, LocationService.swift, HealthDetailSheet.swift, DropTimelineChart.swift_
