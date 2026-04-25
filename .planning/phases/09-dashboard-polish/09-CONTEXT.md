# Phase 9: Dashboard Polish - Context

**Gathered:** 2026-04-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the home screen and HealthDetailSheet stay in sync with reality in real time, give the timeline chart a legend that explains "silent" vs "overt" plus an in-chart filter for overt drops, and stop duplicate probes within the same minute from polluting the event log.

Requirements covered: CHART-01, CHART-02, CHART-03, POLISH-01, POLISH-02.

CHART-03 (home-screen / chart updates within 1s of a silent failure) is treated as a verification target, not a UX gray area — `@Query` reactivity should already drive this; researcher / planner confirm whether any explicit refresh is needed once probe dedup and the new chart filter state are in place.

</domain>

<decisions>
## Implementation Decisions

### Chart Legend & Terms (CHART-01)

- **D-01:** Render a **compact inline legend** beneath the chart title — two color swatches with the labels "Silent" and "Overt" — alongside an `(i)` info button.
- **D-02:** The `(i)` button opens a **native SwiftUI `.popover`** anchored to the button. Popover content explains plain-English definitions plus one short "Why this matters for the Apple report" line. No sheet, no inline disclosure (dashboard is already vertically dense).
- **D-03:** Keep terminology **"Silent" / "Overt"** in the chart and legend. Plain-English meaning lives in the popover, not in the labels themselves. Matches REQUIREMENTS.md vocabulary.

### Overt-Drop Filter UX (CHART-02)

- **D-04:** The legend chips **are** the filter — tap a Silent or Overt chip to hide/show that series. Single touch target, no second control row above the chart, pattern matches Apple Health/Fitness charts.
- **D-05:** **Hide** (do not dim/fade) the toggled-off series so the chart literally answers CHART-02 ("only silent failures remain visible"). Filter state affects only the chart render — `dropEvents` aggregation stays intact for future analytics.
- **D-06:** Default state on first open: **both Silent and Overt visible**. Most truthful default; the new (i) popover educates users on the difference. Users who only want silent-only opt in.
- **D-07:** Filter state persists via **`@AppStorage`** (e.g. `chartShowSilent`, `chartShowOvert` — Bool each). Same pattern as `omitLocation`. Edge case: if both end up off, chart shows a "No series visible — tap a chip to enable" hint instead of an empty plot.

### Live Wake Mechanism + Scope (POLISH-01)

- **D-08:** Introduce a **new `lastBackgroundWakeTimestamp`** UserDefaults key, written ONLY when the location callback (or future BGAppRefreshTask handler) fires while `UIApplication.shared.applicationState != .active`. Existing `lastActiveTimestamp` left untouched — `LocationService.detectAndLogGap` (LocationService.swift:138) depends on its current write semantics for gap detection.
- **D-09:** `HealthDetailSheet` reads the new key and renders the timestamp row inside a **`TimelineView(.periodic(from: .now, by: 1))`** so the value re-renders every second while the sheet is open. SwiftUI scopes the re-render to that subview only and stops automatically when the view disappears. No Combine, no manual Timer lifecycle.
- **D-10:** Display the wake age as **relative time** ("12s ago", "3m 14s ago", "2h 5m ago") via `Date.RelativeFormatStyle` (or `.timer` style). Live-ticking is the visible signal of the diagnostic — "is the app still alive in the background?". If `lastBackgroundWakeTimestamp` is unset, render "Never (no background wake yet)".

### Probe Deduplication (POLISH-02)

- **D-11:** Deduplicate at the **probe-firing layer** in `ConnectivityMonitor`. `runProbe()` and `runSingleProbe()` consult two new instance properties (`lastProbeStartedAt: Date?`, `lastProbeOutcome: EventType?`) before doing anything else.
- **D-12:** **Skip rule:** return early ONLY when `Date().timeIntervalSince(lastProbeStartedAt) < 60` AND `lastProbeOutcome == .probeSuccess`. If the prior outcome was `.probeFailure` OR `.silentFailure`, allow the next probe to run regardless of how recent — every failure-state moment deserves fresh confirmation.
- **D-13:** **Sliding 60-second window** (not calendar-minute floor) — avoids the boundary edge case where 00:00:59 and 00:01:00 would both fire because they're in different calendar minutes. Single Date comparison.
- **D-14:** **Failures always log.** The dedup rule above never suppresses a logged failure (because it never suppresses the probe attempt that would have produced one). Probe failures and silent failures are the entire evidence stream — POLISH-02's "no two probe entries in the same minute" applies to noisy successes, not failures.
- **D-15:** Update both `lastProbeStartedAt` (at probe START, before await) and `lastProbeOutcome` (at probe COMPLETE, after the `do/catch` resolves) so a probe that's currently in flight blocks a second concurrent probe via the `lastProbeStartedAt` clock alone. This pairs with the existing `capturedStatus`/`capturedInterface`/`capturedVPNState` race-safety pattern in `runProbe()` (ConnectivityMonitor.swift:264-318).

### Claude's Discretion

- **CHART-03 mechanism** — investigate whether the existing `@Query(sort: \ConnectivityEvent.timestamp, order: .reverse)` in `DashboardView` (DashboardView.swift:11-12) already meets the "within 1 second" criterion once probe dedup is in place. If not, planner decides between (a) explicit `modelContext.processPendingChanges()` after `logEvent`, (b) a manual `@Observable` event-count signal on `ConnectivityMonitor`, or (c) `objectWillChange` trigger. No preference yet — pick the lowest-blast-radius option that passes verification.
- **Background-wake detection mechanism** — `UIApplication.shared.applicationState` query inside `LocationService.locationManager(_:didUpdateLocations:)` vs an explicit `isBackground: Bool` flag flipped by `UIApplication.didEnterBackgroundNotification` / `willEnterForegroundNotification`. Planner picks; the captured timestamp semantics are the same either way.
- **Popover copy for (i) button** — exact wording of the Silent/Overt definitions plus the "Why this matters" line. Suggested draft: *"Silent: modem reports connected, but the network probe failed — the 'attached but unreachable' bug. Overt: NWPathMonitor reported the connection went down. Silent failures are the core evidence for Apple."* Planner refines.
- **Legend chip visual treatment** — exact appearance of "off" state (greyed swatch, strikethrough, opacity 0.4, etc.). Use whatever matches Apple's HIG / system patterns.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project specs
- `.planning/PROJECT.md` — Core value (silent-failure evidence for Apple), constraints, key decisions through v1.2.
- `.planning/REQUIREMENTS.md` §"Chart & Dashboard (CHART)" — CHART-01, CHART-02, CHART-03 acceptance criteria.
- `.planning/REQUIREMENTS.md` §"Polish (POLISH)" — POLISH-01, POLISH-02 acceptance criteria.
- `.planning/ROADMAP.md` §"Phase 9: Dashboard Polish" — Goal, success criteria 1-5, dependencies on Phase 8.

### Prior phase artifacts (patterns to follow)
- `.planning/phases/08-vpn-context/08-CONTEXT.md` — VPN state model, `effectiveInterfaceLabel` already wired, capture-timing pattern (sync outside `Task`, async inside).
- `.planning/phases/08-vpn-context/08-03-PLAN.md` — `currentVPNState` `@Observable` binding pattern; reuse for any new live-state additions.

### Codebase touchpoints
- `CellGuard/Views/DropTimelineChart.swift` — entire file is the chart surface. Today renders implicit Charts legend via `chartForegroundStyleScale`. Add custom legend chips (D-01, D-04), hide-by-series filter (D-05), `@AppStorage` filter persistence (D-07), `(i)` popover button (D-02). The `dropEvents` filter (line 48) and `buckets` aggregation (line 67) stay unchanged — filter only affects render path.
- `CellGuard/Views/DashboardView.swift:38-47` — "Drop Timeline" section currently wraps `DropTimelineChart(events: allEvents)`. Legend + (i) button live near the "Drop Timeline" caption.
- `CellGuard/Views/HealthDetailSheet.swift:106-113, 179-184` — "Last Background Wake" row + `lastWakeText` computed property. Replace with `TimelineView` block reading the new `lastBackgroundWakeTimestamp` key and rendering relative time (D-08, D-09, D-10).
- `CellGuard/Services/LocationService.swift:84, 117-120, 138` — `lastActiveTimestamp` write sites. Add NEW `lastBackgroundWakeTimestamp` write conditionally on `applicationState != .active`. Do NOT alter `lastActiveTimestamp` writes — gap detection at line 138 depends on them.
- `CellGuard/Services/ConnectivityMonitor.swift:227-252` — `startProbeTimer`, `stopProbeTimer`, `runSingleProbe` entry points. Add `lastProbeStartedAt`/`lastProbeOutcome` instance properties.
- `CellGuard/Services/ConnectivityMonitor.swift:264-330` — `runProbe()` body. Insert dedup guard at the top (before line 266 captures); update `lastProbeStartedAt` immediately and `lastProbeOutcome` after the `do/catch` resolves. Pairs with the existing capture-state-before-await pattern.

### Memory observations folded in
- `2026-03-15` Phase 3 polish-issues memory — directly addressed by D-08, D-09, D-10 (HealthDetailSheet live wake) and D-11..D-15 (probe dedup).
- `2026-04-20` UI feedback memory — directly addressed by D-01, D-02, D-03 (legend & terms) and D-04, D-05 (overt-drop filter UX).

No external ADRs — requirements fully captured here and in REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`@Query` reactive event stream** in `DashboardView` (line 11-12) — SwiftData drives drop count cards, last-drop row, and chart from a single sorted query. CHART-03's "update within 1 second" likely comes for free here once probe dedup is in.
- **`@AppStorage("omitLocationData")`** pattern in `DashboardView:15` — exact template for the new `chartShowSilent` / `chartShowOvert` filter persistence.
- **`@Observable` services** (`ConnectivityMonitor`, `MonitoringHealthService`, `LocationService`, `ProvisioningProfileService`) — already drive the dashboard's live VPN, radio tech, health-status, and certificate-expiry rows. New live-wake binding follows the same model.
- **Capture-state-before-await race-safety pattern** in `runProbe()` (lines 264-269) — `capturedStatus`/`capturedInterface`/`capturedVPNState` snapshotted before `await`. Probe dedup integrates cleanly: capture `lastProbeStartedAt` at the same moment.
- **500ms path-change debounce** in `handlePathUpdate` (Phase 2) — already absorbs path-change flapping. Probe-trigger dedup handles the orthogonal case of multiple wake sources firing close together.
- **Phase 8 `effectiveInterfaceLabel`** computed override — proves the codebase pattern for "transform raw model state into a UI-ready label." Useful precedent for any new computed display values in this phase.

### Established Patterns

- **`Network.NWPath` qualification** required everywhere (Network + NetworkExtension both export the type). Continue using fully qualified `Network.NWPath`.
- **No SwiftData migration for additive optional fields** (Phase 7, Phase 8 confirmed) — not directly relevant to Phase 9 since no schema changes are anticipated, but means a new `wakeReason: WakeReason?` field could be added later without migration if scope grows.
- **`@MainActor` ConnectivityMonitor** — all probe/log work is main-actor-isolated. New dedup state (`lastProbeStartedAt`, `lastProbeOutcome`) lives on the same actor; no concurrency primitives needed.
- **`isDropEvent($0)` helper** (DropClassification.swift) — used by both DashboardView drop-count cards and DropTimelineChart. Filter UX must NOT alter what counts as a "drop" — only what the chart renders.

### Integration Points

- **`DropTimelineChart` props** — currently `let events: [ConnectivityEvent]`. Add NO new required parameter; read filter state from `@AppStorage` inside the view. Keeps the call site in `DashboardView` unchanged.
- **`HealthDetailSheet` data sources** — already reads from `monitor`, `locationService`, `healthService`, `profileService` via `@Environment`. The new `lastBackgroundWakeTimestamp` is plain `UserDefaults` (matches existing `lastWakeText`). No new env injection.
- **`LocationService.locationManager(_:didUpdateLocations:)`** — single insertion point for the background-wake conditional write. Co-locates with the existing `lastActiveTimestamp` update at line 117-120.
- **`ConnectivityMonitor.runProbe()`** — single insertion point for the dedup guard. No call-site changes needed at `startProbeTimer`/`runSingleProbe`/`startProbeTimer`'s delayed-launch task.

</code_context>

<specifics>
## Specific Ideas

- The user explicitly wants the **legend AND the filter to be the same control** (tapped chips) — not a separate filter row. Single discoverable surface, matches Apple's first-party chart UX.
- The user explicitly wants **plain-English explanations behind a tap**, not always-on captions. The (i) popover keeps the chart visually clean and adds context only on demand. Definitions should frame Silent as "the bug we're documenting for Apple."
- The user explicitly wants the **default chart view to show both series** even though the app's reason-to-exist is silent failures — preserves the truthful "what actually happened" story; the user opts in to silent-only when they want focus.
- The user explicitly wants **`lastBackgroundWakeTimestamp` to mean what it says** — only true background wakes count. The existing `lastActiveTimestamp` (used by gap detection) stays exactly as-is.
- The user explicitly wants **failures to never be suppressed by dedup** — even two failures within 60 seconds both deserve to be logged. The dedup rule's only purpose is removing redundant `.probeSuccess` noise.
- The user requested an **explanation of why background-only wakes are recommended over a hybrid "show both" approach** — the rationale (mid-discussion) is preserved in the discussion log: HealthDetailSheet's role is to answer one question (is the app healthy in background?), and a single trustworthy number serves that better than two competing metrics.

</specifics>

<deferred>
## Deferred Ideas

- **Live "VPN: connecting" pill on the dashboard** — flagged as "deferred to Phase 9" in the Phase 8 CONTEXT.md but not selected as a gray area for this phase. If wanted, fold via a follow-up quick task or carry to v1.4.
- **`detectAndLogGap` migration to `lastBackgroundWakeTimestamp`** — eventually gap detection might be more accurate using background-wake-only timestamps, since foreground location callbacks shouldn't reset the gap clock either. Out of scope for Phase 9; revisit when REPORT-01 surfaces gap-counting accuracy issues in Phase 10.
- **Per-series chart subtitle showing counts** (e.g. "Silent: 14 · Overt: 38") — would pair nicely with the legend chips. Not selected for this phase; could land in Phase 10's analytics surface.
- **Chart accessibility audit** — VoiceOver labels for chips and individual bar marks. Add to v1.4 polish if not naturally covered by SwiftUI defaults.
- **`BGAppRefreshTask` handler also writing `lastBackgroundWakeTimestamp`** — Phase 9 codifies the new key and the location-callback write site. If/when BGAppRefreshTask is added (currently registered but not deeply utilized), it should write the same key. Note for whoever picks that up.

</deferred>

---

*Phase: 09-dashboard-polish*
*Context gathered: 2026-04-25*
