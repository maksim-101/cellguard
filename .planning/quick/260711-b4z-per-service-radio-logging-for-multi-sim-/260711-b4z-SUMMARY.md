---
phase: quick-260711-b4z
plan: 01
subsystem: connectivity-monitoring
tags: [coretelephony, dsds, multi-sim, migration-safety, evidence-export]
dependency-graph:
  requires: []
  provides:
    - RadioServiceSnapshot (per-service radio model)
    - ConnectivityMonitor.captureRadioSnapshot()
    - ConnectivityMonitor.radioServicesSelfCheck()
    - ConnectivityEvent.radioServicesJSON / radioChangeService
  affects:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift
    - CellGuard/Views/HealthDetailSheet.swift
tech-stack:
  added: []
  patterns:
    - "Deterministic tie-break for ambiguous system state (dataServiceIdentifier -> sorted-key fallback)"
    - "Per-entity state comparison instead of single-scalar comparison to avoid phantom transitions"
key-files:
  created:
    - CellGuard/Models/RadioServiceSnapshot.swift
  modified:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift
    - CellGuard/Views/HealthDetailSheet.swift
decisions:
  - "Primary line selection: dataServiceIdentifier when non-nil, else lowest sorted service id (stable, documented as a guess)"
  - "radioServices/radioChangeService encoded as structured JSON array in export, ungated by the privacy toggle (opaque service id carries no subscriber identity)"
  - "One JSON string column (radioServicesJSON) instead of per-service columns, since service count is device-dependent"
metrics:
  duration: "~50min"
  completed: "2026-07-11"
status: complete
---

# Phase quick-260711-b4z Plan 01: Per-service radio logging for multi-SIM (DSDS) Summary

Fixed a data-integrity bug where `serviceCurrentRadioAccessTechnology?.values.first` sampled an
arbitrary SIM service on every capture (Dictionary.values has no defined order), and added
deterministic per-service radio logging so the secondary Tello eSIM's state can be correlated
against the 317 logged silent failures.

## What Changed

**The bug fix.** All three call sites that read `serviceCurrentRadioAccessTechnology?.values.first`
(`startMonitoring`, `setupRadioTechObserver`, the old `captureRadioTechnology()`) are gone. They are
replaced by `ConnectivityMonitor.captureRadioSnapshot()`, a single CoreTelephony read that:
- Enumerates every provisioned service by unioning `serviceCurrentRadioAccessTechnology` keys,
  `serviceSubscriberCellularProviders` keys (deprecated API, keys only — CTCarrier values are junk
  post-iOS 16.4), and `dataServiceIdentifier` (belt-and-braces so the data line can never drop out).
- Selects the primary/data line deterministically: `dataServiceIdentifier` when iOS provides it,
  else the lowest sorted service id as a documented, stable tie-break.
- Returns a `RadioServiceSnapshot` per service, recording an unregistered line as an **explicit
  nil `tech`**, never an omitted entry.

**The phantom-transition fix.** `setupRadioTechObserver` now reads the notification's `object` —
confirmed by the SDK header to be the changed service's identifier — and suppresses a
`.radioTechChange` event only when **that specific service's** tech is unchanged (compared against
`lastTechByService[svc]`, seeded at `startMonitoring()`). Previously the comparison was against a
single `currentRadioTechnology` scalar, so a dictionary-iteration-order flip between two SIM
services could fire a phantom event that never physically happened. If the notification's object is
somehow absent, the code falls back to comparing the primary tech (today's pre-fix behavior) rather
than dropping the event — a logged event with `radioChangeService == nil` is recoverable evidence, a
dropped event is not.

**Data model (migration-safe).** `ConnectivityEvent` gains two **optional** fields with nil
defaults — `radioServicesJSON: String?` and `radioChangeService: String?` — following the same
migration-safe pattern already proven by `vpnInterface`/`throughputKbps` in this store (SwiftData
backfills new optional attributes with nil, no declaration default required). `radioTechnology`'s
meaning narrows to "the primary/data line only" from this change onward; a computed
`radioServices: [RadioServiceSnapshot]?` accessor decodes the JSON column on read.

**Export.** `radioServices` and `radioChangeService` encode as a **structured JSON array** in
`Codable.encode(to:)` — not a stringified blob — so the export file an Apple engineer reads needs
no post-processing. Both fields are placed **outside** the `!omitLocation` privacy gate: a
CoreTelephony service identifier is an opaque local slot handle (no IMSI/ICCID/MSISDN, no
subscriber/SIM/device identity), and gating it would strip this evidence from the very export a
user is most likely to send (the privacy-on export).

**UI.** `EventDetailView` relabels "Radio Tech" → "Radio Tech (data line)" and adds a "SIM Services"
section (shown only when `radioServices` is non-nil and non-empty) listing each service's role
(Data Line / Other Line), tech — or an explicit **"Not registered"**, never blank — and the opaque
service id in a caption; `radioChangeService` is shown when present. Legacy events (both fields nil)
render exactly as before. `HealthDetailSheet` gets a "Run Radio Services Self-Check" button modeled
directly on the existing VPN self-check block, with an outcomes legend explaining what each result
means for reading the evidence (registered/unregistered line visible vs. invisible, primary-line
guess vs. authoritative).

**Self-check.** `ConnectivityMonitor.radioServicesSelfCheck()` dumps the raw `dataServiceIdentifier`,
every `serviceCurrentRadioAccessTechnology` entry, the `serviceSubscriberCellularProviders` keys,
the resolved primary + which rule chose it, and the provisioned-but-unregistered set — printing only
what the APIs returned, no inference, no scanning detection (per the plan's out-of-scope list: no
signal strength, no PLMN-scan detection, no NAS reject causes — none of these have a public API).

## Verification — What Was Actually Observed vs. What Remains Unverified

**Machine-verified by Claude in this session (ran the commands, read the output):**
- `RadioServiceSnapshot` encode/decode round-trip — compiled the real production
  `RadioServiceSnapshot.swift` standalone with `swiftc` plus a throwaway harness. Confirmed:
  the nil-tech unregistered-line case round-trips correctly, `encode([])` returns `nil` (not
  `"[]"`), `decode(nil)` returns `nil`, and encoding is deterministic (`.sortedKeys`).
  Output: `PASS round-trip: [{"isPrimary":true,"service":"0000000100000001","tech":"CTRadioAccessTechnologyNRNSA"},{"isPrimary":false,"service":"0000000100000002"}]`
- Simulator build (`iPhone 17 Pro Max`, `iOS 26 SDK`): **BUILD SUCCEEDED**, no new warnings from
  any of the four changed/created files.
- Device build (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`): **BUILD SUCCEEDED**. Exactly
  the two expected `serviceSubscriberCellularProviders` deprecation warnings and nothing else
  (`ConnectivityMonitor.swift:385` and `:941` — the two call sites that read its keys).
- `grep` confirms no arbitrary `.values.first` read remains in executable code in
  `ConnectivityMonitor.swift`, and that `dataServiceIdentifier`, `lastTechByService`, and
  `radioServicesSelfCheck` are all present.
- **Migration smoke test, run against a real populated store** (not synthetic): booted the
  iPhone 17 Pro Max simulator with an existing 53-row `ZCONNECTIVITYEVENT` table from an earlier
  build (June 2026 data), copied `default.store`/`-wal`/`-shm` aside as a safety net, installed
  the NEW build over the existing container (did not erase, did not uninstall), launched, and
  confirmed:
  - App stayed running (no crash, `launchctl list` showed the process alive throughout).
  - Row count immediately after install/launch was still exactly **53** — zero rows lost.
  - `PRAGMA table_info` lists both `ZRADIOSERVICESJSON` and `ZRADIOCHANGESERVICE` — proving a
    real lightweight migration ran, not a silent store recreation.
  - No `134110` anywhere in the launch window's system log.
  - After enabling monitoring (`monitoringEnabled` UserDefaults flag, the same flag the app's own
    "Start Monitoring" button sets) and letting a real probe cycle run, a **new** event was logged
    with `ZRADIOSERVICESJSON IS NULL` — confirming the no-cellular-services path (the simulator has
    no SIM services) neither crashes nor fabricates data, it correctly stores nil.
- Task-level `<automated>` verify blocks for all three tasks passed as specified in the plan.

**NOT verified by Claude — requires the physical iPhone 17 Pro Max with the Tello line ON
(this is the blocking checkpoint the user must complete):**
- That `dataServiceIdentifier` returns the expected (Swisscom) line at runtime on a live dual-eSIM
  device. The SDK header confirms the property exists and is public/non-deprecated; its runtime
  behavior on DSDS is untested by this session.
- That `serviceSubscriberCellularProviders` still enumerates BOTH service keys on iOS 26 hardware.
  If it returns nothing, only registered services are visible and an unregistered second line
  becomes invisible — inverting how the evidence must be read.
- That the "SIM Services" section in `EventDetailView` actually renders two real lines with correct
  labeling on-device (the simulator has zero cellular services, so this session only confirmed the
  section is correctly *omitted* for that state, not that it correctly *renders* for a populated
  one).
- Screenshot/visual confirmation of the self-check alert layout on real hardware — **the plan's
  Task 3 `<human-check>` item ("Screenshot of the simulator event detail + self-check alert
  rendering without layout breakage") could not be captured in this session**: this execution
  environment has no attached display/window session for the iOS Simulator app (`System Events`
  reports zero Simulator windows even with the app process running), so no UI taps or screenshots
  of app screens beyond the initial home screen were possible. The SwiftUI code was reviewed
  carefully (conditional `Section`/`ForEach` gates matching existing patterns in the file) and both
  builds succeeded with no warnings from these files, but actual on-screen rendering of the new
  "SIM Services" section and the self-check alert was **not observed** — only inferred from a clean
  compile. This is exactly what the blocking checkpoint's step 5 ("Open any recent event → confirm
  a 'SIM Services' section lists BOTH lines") is for.

All of these on-device unknowns are settled by the single self-check screenshot requested in the
blocking checkpoint below.

## Deviations from Plan

**1. [Environment limitation, not a deviation rule] UI screenshot verification unavailable.**
The plan's Task 3 verify step asked for a simulator screenshot of the event detail view and
self-check alert. This session's execution environment has no GUI/display session attached to the
iOS Simulator (confirmed via `osascript`/System Events reporting zero windows for the running
Simulator process), so no UI navigation or screenshots beyond the initial home screen were
possible. This does not block the migration smoke test (which only needed `sqlite3`/`xcrun simctl`
CLI access, not UI interaction) but does mean the actual on-screen rendering of the new UI was not
visually confirmed by Claude. Documented above and left for the user's on-device verification.

No other deviations — the plan was executed exactly as written for Tasks 1–3.

## Migration Safety (the #1 constraint)

Both new `ConnectivityEvent` fields (`radioServicesJSON`, `radioChangeService`) are `String?` with
nil defaults, following the exact pattern already proven safe by `vpnInterface`/`throughputKbps` in
this store. The migration smoke test above confirms this empirically against a real populated
store: 53 pre-existing rows survived the schema change with zero loss, both new columns appeared,
and no CoreData 134110 error occurred. The user's real device data (100+ days) was never touched by
this session — all testing was against the simulator's store, with a safety-net copy made before
installing the new build.

## Self-Check

- `CellGuard/Models/RadioServiceSnapshot.swift`: FOUND
- `CellGuard/Models/ConnectivityEvent.swift`: FOUND (modified)
- `CellGuard/Services/ConnectivityMonitor.swift`: FOUND (modified)
- `CellGuard/Views/EventDetailView.swift`: FOUND (modified)
- `CellGuard/Views/HealthDetailSheet.swift`: FOUND (modified)
- Commit `65c1da6` (Task 1): FOUND in `git log`
- Commit `2bbe336` (Task 2): FOUND in `git log`
- Commit `ef02d61` (Task 3): FOUND in `git log`

## Self-Check: PASSED

## Next Step

**Task 4 (blocking checkpoint) is for the user, not Claude.** Before installing the new build on
the real device: export current data via ShareLink/AirDrop as an insurance policy. Then install,
enable the Tello eSIM, open Health detail → "Run Radio Services Self-Check", and send a screenshot.
See the plan's checkpoint task for the full verification script.
