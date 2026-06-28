---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: Polish & Analytics
status: complete
stopped_at: v1.3 complete
last_updated: "2026-04-26T12:00:00.000Z"
last_activity: 2026-06-28 -- quick 260628-ope: low-data cellular throughput probe + slowThroughput event
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-25)

**Core value:** Reliably detect and log every cellular connectivity drop — including silent modem failures — to produce irrefutable evidence for Apple's engineering team.
**Current focus:** v1.3 complete — ready for next milestone

## Current Position

Phase: 10 (reports-and-analytics) — COMPLETE
Plan: 1 of 1
Status: Milestone v1.3 complete
Last activity: 2026-04-26 -- Phase 10 implemented and verified (REPORT-01/02, ANALYTICS-01/02)

## Performance Metrics

**Velocity (through v1.2):**

- Total plans completed: 13 (v1.0 + v1.1 + v1.2)
- Total phases shipped: 8 (incl. 06.1 polish)

**v1.3 progress:**

- Phase 8 (VPN Context): 4 plans, complete 2026-04-25.
  - Wave 0 device test deferred to embedded `os_log` self-check in Plan 03 (08-VERIFICATION-WAVE-0.md).
  - Waves 1–3 executed sequentially with build success at each wave gate.

**By Phase (v1.0–v1.2):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01 | 1 | 4min | 4min |
| Phase 02 | 2 | 5min | 2.5min |
| Phase 03 | 3 | 15min | 5min |
| Phase 04 | 3 | 8min | 2.7min |
| Phase 05 P01 | 1 | 1min | 1min |
| Quick 260326-pjn | 1 | 2min | 2min |
| Phase 07 P01 | 1 | 6min | 6min |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

**v1.3 roadmap decisions:**

- Phase numbering continues from v1.2 — first new phase is **Phase 8** (no reset).
- 3 phases derived from 13 requirements at coarse granularity.
- VPN comes first because VPN-01 changes the event pipeline; later phases consume VPN-tagged events without pipeline churn.
- POLISH-01/02 folded into Phase 9 (Dashboard Polish) rather than a standalone phase — they share the dashboard/reactivity surface with CHART-01/02/03.

**Phase 8 execution decisions:**

- BROAD VPN-04 trigger adopted (user override of CONTEXT.md D-06's narrow trigger). Implemented in `runProbe()` catch branch as `effectivelyCellular = (interface == .cellular) || (vpnIsUp && path.usesInterfaceType(.cellular))`.
- Wave 0 device verification deferred to in-app `os_log` self-check inside `captureVPNDetectorBool()` (one-shot dump of `__SCOPED__` keys + matched prefix on first invocation per app launch). User reads Console.app once after enabling VPN to confirm detection works on iOS 26.4.2.

### Pending Todos

- **Replace deprecated CLGeocoder with MKReverseGeocodingRequest** in `AnalyticsView.swift:220, :230` — see `.planning/todos/pending/2026-05-03-replace-clgeocoder-with-mkreversegeocoding.md`.
- **Add TimeToLive sanity check to ProvisioningProfileService** — surface a visible warning when profile TTL < 30 days. See `.planning/todos/pending/2026-05-03-add-timetolive-sanity-check-to-provisioning-profile-service.md`.

### Blockers/Concerns

None.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260627-r9c | VPN A/B instrumentation + probe hardening (GET+body validation, restrictedState, vpnInterface, vpnStateChange events, in-app self-check button) | 2026-06-27 | 771b8fc | [260627-r9c-vpn-ab-instrumentation](./quick/260627-r9c-vpn-ab-instrumentation/) |
| 260627-rtr | Explicit VPN status in event detail (show Disconnected/None) + self-check UI explanation & verdict | 2026-06-27 | a92552e | [260627-rtr-vpn-detail-and-selfcheck-ui](./quick/260627-rtr-vpn-detail-and-selfcheck-ui/) |
| 260628-8tr | Capture Low Data Mode (fix probe-path hardcoded `false` bug) + new per-event Low Power Mode field (model, capture, EventDetailView, JSON export) | 2026-06-28 | 880d680 | [260628-8tr-capture-low-data-mode-fix-hardcoded-fals](./quick/260628-8tr-capture-low-data-mode-fix-hardcoded-fals/) |
| 260628-ope | Low-data cellular throughput probe (100KB Cloudflare `__down` every 5th probe cycle, cellular-only) → `throughputKbps` field + `.slowThroughput` event (<1Mbps); catches "attached but slow" NR-NSA stalls the reachability probe misses | 2026-06-28 | 2f2c68b | [260628-ope-add-low-data-cellular-throughput-probe-1](./quick/260628-ope-add-low-data-cellular-throughput-probe-1/) |
| fast | Count only cellular path-change drops, exclude Wi-Fi handover gaps (overt-drop event records lost interface; isDropEvent gates on cellular) + SwiftData migration fix for `lowPowerMode` declaration default (crash 134110) | 2026-06-28 | a4b92ea | — |
| fast | Seed VPN edge-detector at launch so a pre-existing VPN (Tailscale already connected) reads `.connected` not stale `.connecting` on first probe | 2026-06-28 | c819cd6 | — |
| fast | Probe Latency analytics section — side-by-side Successful vs Failed min/median/mean/max/count (failed = probeFailure + silentFailure); surfaces slow successful probes | 2026-06-28 | 6bb2ab6 | — |
| fast | Discard app-suspension artifacts from probe latency + throughput (wall-clock across background freeze gave 900s+ "latencies"); nil latency / skip throughput beyond probeTimeout+2s; Analytics filters >15s | 2026-06-28 | e68e123 | — |

## Session Continuity

**Last activity:** 2026-06-27 — paused for user to collect on-device data.

**What this session did (field-debugging the live cellular issue, not v1.3 work):**
- Diagnosed & fixed a false-positive `silentFailure` bug: probe reused one URLSession → stale cellular sockets hung to 10s timeout. Fix = per-probe ephemeral session + two-host (Apple + Cloudflare) confirmation. Debug session: `.planning/debug/probe-false-silent-failures.md` (commit `ad991b7`).
- Quick `260627-r9c`: GET+body-validation probe, `CTCellularData.restrictedState`, per-event `vpnInterface`, dedicated `vpnStateChange` events, in-app VPN self-check button (HealthDetailSheet). Commits `d3b79b3`→`771b8fc`.
- Quick `260627-rtr`: event detail always shows VPN status (Disconnected/None); self-check UI explanation + verdict. `a92552e`.
- Cleanup `bef2239`: removed dead Carrier row; gated Cellular Data Access to show only when meaningful.
- All builds green on iOS Simulator. User reinstalled on device; confirmed a NEW-build two-host-confirmed Silent Failure on **NRNSA with no VPN**.

**DIAGNOSIS (well-supported, see memory `project_connectivity_root_causes`):** It is the **iPhone 17 Pro Max + iOS 26 baseband (5G NR-NSA data stall)**. Eliminated by user: 3 units, 3 SIMs (physical/home eSIM/German travel eSIM), 2 carriers, 2 countries, with/without VPN, with/without restored backup, carrier confirms no other reports. VPNs fully exonerated.

**Deliverable written:** `apple-support-dossier-2026-06-27.md` (in repo root AND `~/code/flashtype-workspace/`) — full evidence/escalation/remediation reference for senior Apple support. Backed by 8 research reports in this session's scratchpad.

**RESUME HERE — waiting on user's on-device data. Next actions in priority order:**
1. **5G Auto/LTE A/B** (highest value): does forcing Settings→Cellular→Voice&Data→5G Auto/LTE drop the confirmed NRNSA silent failures? Clean-on-LTE = pinpoints the NR-NSA subsystem for Apple.
2. Read the user's exported CellGuard CSV/JSON: compute confirmed-silentFailure **rate** per window (baseline vs 5G-Auto; later Tailscale/Proton windows — VPN windows are now low-value).
3. Optional offers still open: render the dossier to **PDF**; **iOS 26.6 / iOS 27 public-beta** test (NOT dev beta); capture a **sysdiagnose** timed to a failure + file **Feedback Assistant** report.

**Git:** branch `feature/apple-support-script`, **needs push** (commits since `2240e0e`). Pre-existing unrelated uncommitted `project.pbxproj` (M) and `apple-support-script-2026-05-23.html` (untracked) were NOT touched this session — leave them.

Resume file: .planning/debug/probe-false-silent-failures.md
