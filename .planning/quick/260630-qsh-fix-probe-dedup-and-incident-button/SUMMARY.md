---
quick_id: 260630-qsh
slug: fix-probe-dedup-and-incident-button
date: 2026-06-30
branch: feature/data-capture-fidelity
status: complete
---

# Summary — probe dedup + incident button fix

Both bugs fixed and verified to compile.

- **Bug 1 (dedup race):** added `probeInFlight` guard in `ConnectivityMonitor.runProbe()`.
  Concurrent reentrant probes are now coalesced to one execution, so a single moment can
  no longer be logged as N identical-timestamp events. Commit `3ff4cf7`.
- **Bug 2 (button feedback):** `Log Incident Now` now pulses haptic on every tap via a
  monotonic `incidentTapCount`, re-arms the confirmation per press, and is never disabled.
  Commit `2ce0d78`.

**Verification:** `build_sim` (scheme CellGuard, iPhone 17 Pro Max / iOS 26.5) →
SUCCEEDED, 0 warnings, 0 errors. Not installed/run on device (signing out of scope).
Runtime behaviour (no duplicate clusters in a fresh export; rapid-tap haptics) to be
confirmed on the next real-device capture run.

**Not pushed** (feature branch, per request).

**Follow-up noted, not done:** the `pathUsesCellular` vs `interfaceType` inconsistency and
`degraded=true` with `throughputKbps=null` from the 06-30 export analysis are separate
data-quality items, deferred.
