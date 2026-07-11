---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: Polish & Analytics
current_phase: 10
current_phase_name: reports-and-analytics
status: complete
stopped_at: "ROOT CAUSE FOUND (2nd eSIM / DSDS contention). quick-260711-e5s checkpoint open; manual-network-selection experiment running; Maengelruege drafted not sent."
last_updated: "2026-07-11T08:35:32.430Z"
last_activity: 2026-07-11
last_activity_desc: "Root cause isolated: the unregistrable Tello eSIM starves the data line via DSDS RF contention (confirmed by iOS's own Poor Cell Coverage battery telemetry). Per-service radio logging + severe-latency tier shipped. Apple support script rewritten; Maengelruege drafted."
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

**1. OPEN CHECKPOINT — quick-260711-e5s needs on-device verification.** Severe-latency tier is built and migration-verified but never exercised on real cellular (the simulator has no cellular path, so `lastThroughput` never populates and the rule always takes the conservative no-data branch). The load-bearing check is the NEGATIVE one: **in genuinely weak-coverage spots, slow probes must stay "Probe Success (degraded)", NOT `.severeLatency`.** If bad coverage starts producing severeLatency drops, the throughput gate is broken and the data is not defensible to Apple.

**2. BIGGEST EVIDENCE GAP — no sysdiagnose captured during an active failure.** With Apple's cellular/baseband logging profile installed (developer.apple.com/bug-reporting/profiles), a sysdiagnose taken *during* a silent failure is the one artefact Apple Engineering actually reads (PLMN search cycles, NAS reject causes, retry timers). **Sequencing trap:** the manual-network-selection experiment now running may FIX the phone, leaving no failure left to capture. Mitigation: install the profile now; if manual mode works, deliberately revert Tello to automatic for one day to capture a failure sysdiagnose. Note the exact timestamp for correlation with the CellGuard log.

**3. LEGAL CLOCK RUNNING — Mängelrüge drafted but NOT SENT.** Art. 201 OR requires notice of a defect "immediately" upon gaining certainty; the Bundesgericht is strict (≈7 days has been treated as only barely timely) and late notice means the defect is deemed accepted, irrebuttably. Draft is at `maengelruege-2026-07-11.html` (first written notice; certainty-timing argument dated 11.07.2026). Needs: seller entity copied off the invoice (do NOT guess), placeholders filled, Einschreiben, review by Stiftung für Konsumentenschutz or a lawyer.

**4. The 2026-05-23 support script is factually WRONG and still on disk (untracked).** It argues "defect in my specific unit" — now known false. Superseded by `apple-support-script-2026-07-11.html`. Delete or archive it so it cannot be grabbed by mistake.

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
| 260628-rpt | Option H "Cellular Health" home redesign: dynamic 0–100 score (clean-probe %, cellular-only via isExpensive, Wi-Fi excluded) — Overall + Last-24h rings + "vs usual" verdict + probe denominator + failure-mode legend rows; Stall series added to Drop Timeline (moved to Analytics) + Data Stalls Key Driver; new HealthScore.swift helper. Self-verified via simulator screenshots. | 2026-06-28 | 9d672a6 | [260628-rpt-option-h-cellular-health-home-redesign-w](./quick/260628-rpt-option-h-cellular-health-home-redesign-w/) |
| fast | Severe-throughput tier: 3-tier classification (>=1Mbps ok / 200k-1M slowThroughput / <200k severeThroughput); severeThroughput (rawValue 8) counts as a drop + notifies; kept distinct from silentFailure | 2026-06-28 | 93f7a66 | — |
| 260630-qsh | Fix duplicate same-timestamp event clusters (probeInFlight guard coalesces reentrant @MainActor probes — 6x@09:35:01 etc. in 06-30 export) + Log-Incident button registers every tap with haptic (monotonic incidentTapCount, never disabled). Simulator build verified. | 2026-06-30 | 3ff4cf7 | [260630-qsh-fix-probe-dedup-and-incident-button](./quick/260630-qsh-fix-probe-dedup-and-incident-button/) |
| 260711-b4z ✅ | Per-service (DSDS multi-SIM) radio logging. Fixes `.values.first` non-determinism — with 2 SIM services the app sampled an ARBITRARY line, corrupting `radioTechnology` and emitting phantom `radioTechChange` events. Now: primary line resolved via `dataServiceIdentifier` (stable sorted-key fallback); all provisioned services enumerated (unregistered line = absent key, per Apple's own doc); `radioChangeService` records WHICH line changed; per-service array in JSON export; "SIM Services" in EventDetailView + Radio Services Self-Check. Migration smoke-tested on a populated store (53 rows, 0 lost, no 134110). **ON-DEVICE VERIFIED 2026-07-11** — both risky assumptions confirmed by the user's self-check screenshot: `dataServiceIdentifier` returns a real value on iOS 26, and the deprecated `serviceSubscriberCellularProviders` DOES still enumerate service keys. Device shows `0000000100000001 = Not registered` (Tello) / `0000000100000002 = NRNSA` (Swisscom). Checkpoint CLOSED. | 2026-07-11 | ef02d61 | [260711-b4z-per-service-radio-logging-for-multi-sim-](./quick/260711-b4z-per-service-radio-logging-for-multi-sim-/) |
| 260711-e5s 🔶 | Severe-latency drop tier gated on throughput. A cellular probe that succeeds but takes >5s over a radio that measured >=1Mbps within the freshness window (~6min) is now `.severeLatency` (rawValue 12) — a DROP — instead of a silently-counted "success". Slow probes on poor/unknown throughput stay non-drops (never blame the modem for weak coverage). New `SevereLatencyRule.swift` (Foundation-only, machine-tested via standalone swiftc: all 4 branches + boundaries pass). `referenceThroughputKbps` recorded on both outcomes for audit. Wired through HealthScore denominator/stall bucket, DropTimelineChart, AnalyticsView, EventDetailView, SummaryReportView. Migration smoke-tested on the populated device-mirror simulator store (86→91 rows across the test, 0 lost, `ZREFERENCETHROUGHPUTKBPS` column confirmed present, 0 historical rows reclassified, no 134110). **Awaiting on-device verify (needs real cellular throughput samples — simulator has no cellular path).** | 2026-07-11 | a3af190 | [260711-e5s-severe-latency-tier-gated-on-throughput](./quick/260711-e5s-severe-latency-tier-gated-on-throughput/) |

## Session Continuity

**Last session:** 2026-07-11T08:35:32.424Z
**Stopped at:** quick-260711-e5s complete, blocking checkpoint pending user on-device verification

**Latest activity:** 2026-07-11 — quick 260711-e5s: severe-latency drop tier gated on throughput. All 3 tasks committed (`9cbf2a2`, `0f0bc39`, `a3af190`); migration smoke test passed on the populated simulator store. **Blocked on the plan's blocking checkpoint** — needs the user to install on the physical iPhone 17 Pro Max, run on cellular for ~10min, and confirm a real slow-probe episode is classified `.severeLatency` (not "Probe Success") with a Reference Throughput >=1.0 Mbps, AND that genuinely weak-signal locations do NOT produce false severeLatency events. See `.planning/quick/260711-e5s-severe-latency-tier-gated-on-throughput/260711-e5s-SUMMARY.md` for full detail.

---

## ⚡ ROOT CAUSE FOUND — read this before touching anything (2026-07-11)

**This session stopped being an app-development session and became a field investigation. The app is now instrumentation for a live Apple escalation. Act accordingly.**

**The cause of the cellular drops is the second eSIM (Tello, US voice-only line), not the iPhone hardware.** It cannot register on any Swiss network, so it searches continuously. iPhone is DSDS — both lines share ONE RF chain — and paging/signalling/network-search on the idle line outranks packet data on the active line. Result: the Swisscom line reports full bars + 5G while passing zero data for hours, and iOS never detects it.

**Evidence (all confirmed, not speculation):**
- Tello **OFF** → zero issues, sustained, even with Tailscale + ProtonVPN reinstalled. Tello **ON** → issues return.
- Failure occurs with Tello's Voice & Data on **5G *and* on LTE** → **the "5G SA hunting" hypothesis is RULED OUT.** It's the network search itself, not the bands.
- **Region locale is a RED HERRING** — user set region back to US, issue did not return on that account. The 2026-07-08 "region=CH is the fix" conclusion was WRONG. Do not resurrect it.
- **iOS's own battery telemetry corroborates it** (Settings → Battery → "Poor Cell Coverage"): the ONLY two days at ~zero are Wed 7/8 and Fri 7/10 — the exact two days Tello was off (dates VERIFIED). All other days 1.5–3.5%. This proves the idle line is actively burning radio, not dormant. **This is Apple's own accounting and is the strongest single artefact in the case** — it cannot be dismissed as third-party instrumentation.

**Consequences — these change the strategy, not just the diagnosis:**
- The "defect in my specific unit" framing is **DEAD**. Three phone swaps reproduced it because *every* iPhone would.
- **A REPLACEMENT HANDSET WILL NOT FIX THIS.** Do not pursue ERS. Do not accept a like-for-like swap as closure — it solves nothing and ends the case. Ersatzlieferung is therefore a worthless remedy; only a software fix or Wandelung (refund) actually helps.
- The defect that survives is still Apple's and still serious: in a **supported, advertised configuration** (Dual SIM), the device silently reports full 5G while carrying zero data for up to 7 hours, and iOS neither detects it, surfaces it, nor offers any control to deprioritise an idle line.
- Reframe the escalation as **"I have isolated a deterministic reproduction"** — not "it was my eSIM." The sysdiagnose already contains the second eSIM; concealment is impossible and would destroy credibility.

**EXPERIMENT RUNNING (started 2026-07-11):** Tello line **ON**, Network Selection → **Manual → Sunrise**. Tello shows **zero bars** (confirmed) = it did NOT register = this is the intended test (pinned to an unjoinable network, so the PLMN search should be suppressed). Pre-registered predictions:
- **Poor Cell Coverage stays ~0 with the line ON** → manual mode killed the hunt → **iOS had a remedy available all along and neither applied nor surfaced it.** Devastating for Apple.
- **Poor Cell Coverage returns to 1.5–3.5%** → iOS silently ignored manual selection and fell back to automatic scanning → a defect in its own right.

**What to do on resume:** ask for the Poor Cell Coverage battery chart + CellGuard drop counts for the days since 2026-07-11. Both outcomes are findings. Do NOT re-litigate the root cause.

**Unexplained, worth chasing:** the three multi-hour "zombie modem" events all start at **04:49 / 04:55 / 05:09** — same time of day. A ~24h retry timer (3GPP **T3245**, the forbidden-PLMN retry timer, max 24h) would produce exactly this. Falsifiable via baseband logs; present to Apple as a hypothesis for *them* to test, not as a conclusion.

**Hard constraint learned this session:** there is **NO public API for signal strength on iOS** (not CoreTelephony, not anywhere in the iOS 26 SDK). Private APIs (`CTGetSignalStrength`, status-bar scraping) are **rejected** — a diagnostic tool that reads undocumented internals hands Apple a free way to dismiss the entire dataset. Do not go looking again. Throughput is the only permitted signal-quality proxy, which is exactly why the `.severeLatency` tier is gated on it.

**Deliverables written this session (commit `cae76ec`):**
- `apple-support-script-2026-07-11.html` — rebuilt around the reproduction; drops the ERS ask; coaches refusal of a swap.
- `maengelruege-2026-07-11.html` — first written notice under Art. 201 OR; reserves the Art. 205/206 choice of remedy; pre-emptively kills Ersatzlieferung as a non-remedy; notes Swiss law has **no statutory right to repair** (Apple cannot force a repair loop). **NOT SENT — see Blockers #3.**

**Previous activity:** 2026-07-11 — quick 260711-b4z: per-service DSDS radio logging built; blocked on user's on-device self-check screenshot.

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

Resume file: None
