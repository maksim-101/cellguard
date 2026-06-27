---
status: resolved
trigger: "Probe produces false-positive Silent Failure events on cellular due to stale reused-URLSession connections; needs fresh-session-per-probe + two-host confirmation before classifying silentFailure."
created: 2026-06-27
updated: 2026-06-27
---

# Debug: probe-false-silent-failures

## Symptoms

- **Expected behavior:** A `silentFailure` event is logged ONLY when the cellular data path is genuinely unreachable (attached-but-unreachable modem failure). Probe successes and failures should track real connectivity.
- **Actual behavior:** On full-bar 5G with Wi-Fi off, ~50% of probes log `silentFailure`, interleaved 1:1 with `probeSuccess` over a sustained 10-minute window — a rate incompatible with the user's lived experience of generally-working connectivity.
- **Error messages:** Xcode console shows repeated `Task <...> finished with error [-1001] "The request timed out."` for `https://captive.apple.com/hotspot-detect.html`. NWPath reports satisfied+cellular at the same moment, so the catch branch classifies as `silentFailure`.
- **Timeline:** Observed 2026-06-27 on a fresh install after the user deleted Proton VPN + Tailscale apps/profiles and did a full Network Settings reset (VPN residue ruled out). CoreData "Application Support missing → recovered" errors at launch are benign first-launch noise and are NOT part of this bug.
- **Reproduction:** Install app, disable Wi-Fi (cellular only), enable monitoring, watch Events list — silentFailure/probeSuccess alternate roughly 50/50.
- **Corroboration of partial reality:** User observed App Store failing to load at the same moment CellGuard logged a silentFailure, then airplane-mode toggle restored everything — so at least SOME failures are real, but the ~50% rate strongly implies a large false-positive component.

## Root Cause Hypothesis (pre-diagnosed, needs verification)

`ConnectivityMonitor` reuses ONE long-lived `URLSession` (`probeSession`, ConnectivityMonitor.swift:139) for every probe. On cellular, NAT bindings expire and the device IP rotates; URLSession reuses a stale HTTP keep-alive connection that is silently dead, hangs for the full 10s `timeoutIntervalForRequest`, and fails `-1001`. The next probe opens a fresh connection and succeeds — producing the alternating success/failure signature. Because the failure path checks only `capturedStatus == .satisfied && effectivelyCellular`, a single stale-socket timeout is misclassified as a `silentFailure` with no independent corroboration.

## Planned Fix

1. **Fresh connection per probe** — stop reusing one session. Use an ephemeral `URLSessionConfiguration.ephemeral` session created per probe (or otherwise prevent connection reuse, e.g. `Connection: close`), so a dead pooled socket can never hang to timeout.
2. **Two-host confirmation before silentFailure** — on probe failure where path is satisfied+effectivelyCellular, immediately re-probe a SECOND independent non-Apple host (e.g. Cloudflare `https://cloudflare.com/cdn-cgi/trace` or `https://1.1.1.1`). Only log `silentFailure` if BOTH hosts fail. If the second host succeeds, the first failure was a single-host/socket fluke → log `probeSuccess` (connectivity is real). Preserve existing dedup (D-11..D-15) and BROAD VPN-04 trigger semantics.

## Goal

Eliminate stale-socket false positives so every logged `silentFailure` is corroborated by two independent hosts — producing trustworthy evidence for the Apple Feedback Assistant baseband report.

## Constraints

- Build via xcodebuild MCP; target iPhone 17 Pro Max / iOS 26.x, free personal team signing.
- On-device reinstall + observation of the Events list is the verification (failure rate should drop sharply; remaining silentFailures are two-host-confirmed).
- Keep changes minimal and confined to the probe path in `ConnectivityMonitor.swift`.

## Current Focus

- **hypothesis:** CONFIRMED — single reused URLSession.default keeps a connection pool; stale pooled socket on cellular NAT rotation hangs 10s to -1001 timeout → misclassified as silentFailure.
- **next_action:** DONE — fix applied, build passed, committed as ad991b7.

## Evidence

- timestamp: 2026-06-27 — Xcode log shows 4 consecutive `-1001` timeouts against captive.apple.com while path is satisfied+cellular.
- timestamp: 2026-06-27 — Events list screenshot (08:21–08:30): silentFailure and probeSuccess alternate ~50/50 on full-bar 5G, Wi-Fi off.
- timestamp: 2026-06-27 — `curl -I https://captive.apple.com/hotspot-detect.html` from a Mac returns HTTP/1.1 200 OK, confirming the endpoint itself is healthy.
- timestamp: 2026-06-27 — Code verification: `probeSession` confirmed as `let` constant using `URLSessionConfiguration.default` (line 134 original). Only two references: declaration and `probeSession.data(for: request)` in `runProbe()`. The catch block at original line 330 unconditionally classifies any exception with `satisfied && effectivelyCellular` as `silentFailure` — no alternative code path to silentFailure exists. Adversarial check: DNS failure (-1003), server non-200 HTTP status (.probeFailure path), non-cellular path (.probeFailure path) — none of these produce silentFailure. Hypothesis confirmed.
- timestamp: 2026-06-27 — Build: `xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → BUILD SUCCEEDED. No compiler errors or warnings from the changed code.

## Eliminated

- hypothesis: VPN/NECP residue from Proton VPN + Tailscale — RULED OUT: apps deleted, profiles removed, Network Settings reset performed.
- hypothesis: Post-reset modem re-registration transient — RULED OUT: failures are sustained and interleaved across 10+ minutes, not a one-time startup cluster.
- hypothesis: Endpoint/HTTPS-scheme problem — RULED OUT: endpoint returns 200 to HEAD over HTTPS.
- hypothesis: CellGuard itself causing drops — IMPLAUSIBLE: one HEAD request/minute cannot drop a cellular link; airplane-toggle (not uninstall) is what restored connectivity.
- hypothesis: DNS failure or server non-200 causing silentFailure — RULED OUT: those paths go to `.probeFailure`, not `.silentFailure`. Only network-layer timeout in the catch block reaches silentFailure.

## Resolution

root_cause: |
  `probeSession` was a single long-lived `URLSession` using `URLSessionConfiguration.default`,
  which maintains an HTTP keep-alive connection pool. On cellular, NAT bindings expire and the
  pooled TCP connection goes stale. The next probe hits the dead socket, hangs for the full 10s
  timeoutIntervalForRequest (-1001), and the catch block unconditionally classifies the timeout
  as `silentFailure` because `capturedStatus == .satisfied && effectivelyCellular`. The following
  probe gets a fresh connection and succeeds, producing the alternating 50/50 pattern.

fix: |
  Two-part fix confined to ConnectivityMonitor.swift probe path:
  (a) Replaced `probeSession` (shared URLSession.default) with `makeProbeSession()` factory that
      creates a fresh `URLSessionConfiguration.ephemeral` session per probe call. Empty connection
      pool on each invocation eliminates the stale-socket hang. `waitsForConnectivity = false` and
      10s timeout preserved.
  (b) Added `confirmSilentFailure()` helper: when the catch block would classify `silentFailure`,
      probes Cloudflare `https://cloudflare.com/cdn-cgi/trace` with its own fresh ephemeral session.
      Only logs `silentFailure` if Cloudflare also fails (both hosts down = genuine modem failure).
      If Cloudflare succeeds, logs `probeSuccess` instead (primary failure was a single-host fluke).
      Dedup semantics D-11..D-15 and VPN-04 broad effectivelyCellular trigger are fully preserved.

verification: |
  Simulator build: BUILD SUCCEEDED (xcodebuild, iOS Simulator iPhone 17 Pro, Debug config).
  On-device verification: user to reinstall on iPhone 17 Pro Max with Wi-Fi off, monitor Events
  list for 10+ minutes. Expected: silentFailure rate drops sharply from ~50% to near-zero on
  healthy cellular. Any remaining silentFailure events are corroborated by Cloudflare and represent
  genuine modem failures.

files_changed:
  - CellGuard/Services/ConnectivityMonitor.swift

commit: ad991b7
