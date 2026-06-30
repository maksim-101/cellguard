---
quick_id: 260630-qsh
slug: fix-probe-dedup-and-incident-button
date: 2026-06-30
branch: feature/data-capture-fidelity
---

# Fix: probe dedup race + Log-Incident button feedback

Two bugs surfaced while analysing the 2026-06-30 export.

## Bug 1 — duplicate same-timestamp event clusters
`ConnectivityMonitor.runProbe()` is `@MainActor async` and reentrant at every `await`.
With no in-flight guard, overlapping triggers (rapid `logUserIncident()` — each nulls
`lastProbeOutcome` — plus the 60s timer) all pass the success-dedup guard and complete in
the same second. Export showed e.g. 6× silentFailure at `2026-06-30T09:35:01Z`, 7×
degraded probeSuccess at `08:35:19Z`.

**Fix:** `probeInFlight` instance flag. Top of `runProbe()`: `if probeInFlight { return }`.
Set true after the existing success-dedup guard, clear via `defer`. Coalesces concurrent
probes to one. 60s success-dedup guard unchanged. Does not throttle the normal 60s cadence.

## Bug 2 — Log-Incident button feels locked for ~2s
`.sensoryFeedback(.success, trigger: incidentLogged)` only fires on false→true, and the
green "Incident logged" state persists 2s, so re-taps within that window gave no haptic/
visual acknowledgment (taps did still log).

**Fix:** monotonic `incidentTapCount`; increment every tap, drive `.sensoryFeedback` off it
(pulses every press), re-arm the green confirmation each tap, only the last tap's task
clears it. Button never disabled.

## Scope
Two files only: `CellGuard/Services/ConnectivityMonitor.swift`,
`CellGuard/Views/DashboardView.swift`. Simulator build verification. No push.
