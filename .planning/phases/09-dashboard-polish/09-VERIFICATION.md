---
phase: 09-dashboard-polish
verified: 2026-04-25T00:00:00Z
device_uat: 2026-04-26
status: gaps_found
score: 22/22 static must-haves verified; 3 device UAT gaps confirmed (G1 popover truncation, G2 wake-row clipping, G3 6h axis truncation)
overrides_applied: 0
requirement_coverage:
  - id: CHART-01
    source_plan: 09-03
    description: "User can see a legend on the timeline chart that distinguishes silent failures from overt path-change drops"
    status: satisfied_static
    evidence: "DropTimelineChart.swift:252-276 legendBar HStack renders Silent (red) + Overt (orange) chips with color swatches; .chartLegend(.hidden) at line 209 suppresses the implicit Charts auto-legend so chips are the single discoverable surface (D-04). Visual confirmation requires device."
  - id: CHART-02
    source_plan: 09-03
    description: "User can toggle overt path-change drops off in the timeline chart so silent failures stand out"
    status: satisfied_static
    evidence: "@AppStorage chartShowOvert (line 22) flips on chip tap (line 257-259); visibleBuckets (line 124-132) filters out the toggled-off series before passing to Chart(visibleBuckets) at line 193 — hide-not-dim per D-05. Persistence across launches requires on-device confirmation."
  - id: CHART-03
    source_plan: 09-01
    description: "User sees the home-screen drop count and chart update within 1 second of a silent failure"
    status: satisfied_static_pending_uat
    evidence: "EventStore.insertEvent calls try modelContext.save() synchronously at EventStore.swift:26 (byte-identical, git diff empty). DashboardView declares @Query(sort: \\ConnectivityEvent.timestamp, order: .reverse) at lines 11-12 which propagates synchronous SwiftData saves to view consumers within tens of ms. Combined with probe dedup eliminating duplicate .probeSuccess noise, the existing reactivity satisfies CHART-03 — but the <1s budget can only be confirmed on-device."
  - id: POLISH-01
    source_plan: 09-02
    description: "HealthDetailSheet 'Last Background Wake' updates live while the sheet is open"
    status: satisfied_static_pending_uat
    evidence: "HealthDetailSheet.swift:110 wraps the wake row in TimelineView(.periodic(from: .now, by: 1)) and reads UserDefaults key 'lastBackgroundWakeTimestamp' (line 191) which is written by LocationService.swift:132-137 only when applicationState != .active. lastBackgroundWakeText uses Date.RelativeFormatStyle (.named, .abbreviated) and renders 'Never (no background wake yet)' when unset. Live-tick behavior must be confirmed on-device."
  - id: POLISH-02
    source_plan: 09-01
    description: "Duplicate probes within the same minute are deduplicated so the event log doesn't double-count"
    status: satisfied_static_pending_uat
    evidence: "ConnectivityMonitor.swift:281-285 dedup guard returns early ONLY when Date().timeIntervalSince(started) < 60 AND lastProbeOutcome == .probeSuccess (D-12, D-13, D-14). lastProbeStartedAt is set BEFORE await (line 288) so concurrent probes are also blocked. Outcome assignments at lines 315/328/362/374 cover all four logEvent branches. Failures (.probeFailure, .silentFailure) NEVER suppress the next probe. Behavior must be confirmed on-device by foreground/background cycling."
human_verification:
  - test: "POLISH-02 — successes dedup but failures never do"
    expected: "Foreground app, exit to home, return within 30s. Open event log: at most ONE .probeSuccess row in the same minute window. Then put the device into Airplane Mode mid-probe — the .silentFailure / .probeFailure on the next probe MUST be logged even if it's <60s since the prior probe."
    why_human: "Requires running the app on iPhone 17 Pro Max with foreground/background lifecycle and intentional radio interruption — cannot be exercised from CLI."
  - test: "POLISH-01 — TimelineView ticks at 1 Hz on iPhone 17 Pro Max"
    expected: "Open HealthDetailSheet via the health-bar tap. If a background wake has occurred since install, the 'Last Background Wake' relative-time text re-renders at least once per second (e.g. '12 sec ago' → '13 sec ago'). If no wake has occurred yet, the row reads exactly 'Never (no background wake yet)'."
    why_human: "TimelineView 1 Hz re-render is a runtime SwiftUI behavior; cannot be observed from static checks."
  - test: "POLISH-01 — applicationState gate writes only on background wakes"
    expected: "Trigger a 500m significant location change while the app is BACKGROUND-ed (force-quit briefly is fine — sigChange relaunches it). Re-open the sheet — the wake timestamp must update. Conversely, with the app FOREGROUNDED, a foreground location callback must NOT update the timestamp (the row's relative-time should keep counting up from the prior background wake)."
    why_human: "Requires CLLocationManager significant-location-change delivery on a real device while toggling app state — not reproducible from CLI."
  - test: "CHART-01 — legend chips visible AND no duplicate Charts auto-legend"
    expected: "Scroll to 'Drop Timeline'. Two color-coded chips ('Silent' red, 'Overt' orange) render beneath the segmented Picker, alongside an (i) info button. NO second legend renders below the chart plot (the implicit Charts auto-legend must be suppressed by .chartLegend(.hidden))."
    why_human: "Visual confirmation of legend rendering and absence of duplicate Charts auto-legend is a render-output check that requires the simulator/device."
  - test: "CHART-02 — toggle-off filter actually hides series + AppStorage persists"
    expected: "Tap 'Overt' chip → orange bars disappear, only red (silent) bars remain. Tap 'Overt' again → bars return. Then tap BOTH chips off → chart area shows 'No series visible — tap a chip to enable' (D-07). Force-quit and relaunch — the last chip state must persist (AppStorage)."
    why_human: "Filter toggle, render diff, and AppStorage persistence across cold launch are runtime behaviors not visible from static analysis."
  - test: "CHART-01 — popover anchors to (i) button and shows correct copy"
    expected: "Tap (i) → SwiftUI .popover (NOT a sheet) appears anchored to the button. Heading reads 'Drop Types'. Two definition rows (Silent — '“attached but unreachable” bug', Overt — 'NWPathMonitor reported the connection went down'). Below a Divider, the 'Why this matters' subhead is followed by the Apple-Feedback-Assistant rationale line."
    why_human: "Popover anchor + presentationCompactAdaptation behavior is iOS-version- and form-factor-specific; cannot be statically verified."
  - test: "CHART-03 — dashboard updates within 1 second of a logged event"
    expected: "Foreground app on dashboard view. Wait for (or trigger) a real .silentFailure or .probeFailure. The 'Drops (24h)' card and timeline chart MUST update without scrolling, tapping, or backgrounding — visible delay under 1 second."
    why_human: "End-to-end SwiftData @Query propagation latency must be measured on the device; static analysis can only confirm the synchronous save + @Query wiring is in place."
---

# Phase 9: Dashboard Polish Verification Report

**Phase Goal:** Make the home screen and HealthDetailSheet stay in sync with reality in real time, give the timeline chart a legend that explains "silent" vs "overt" plus an in-chart filter for overt drops, and stop duplicate probes within the same minute from polluting the event log. (Requirements: CHART-01, CHART-02, CHART-03, POLISH-01, POLISH-02.)

**Verified:** 2026-04-25
**Device UAT:** 2026-04-26
**Status:** gaps_found (3 device UAT defects — see Gaps Summary)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from PLAN frontmatter `must_haves.truths`, plus ROADMAP success criteria)

| #   | Truth                                                                                                                                                                       | Status     | Evidence                                                                                                                          |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ConnectivityMonitor declares lastProbeStartedAt: Date? and lastProbeOutcome: EventType? (Plan 09-01)                                                                        | VERIFIED   | ConnectivityMonitor.swift:83 + :89                                                                                                |
| 2   | runProbe() begins with dedup guard returning early ONLY when Date().timeIntervalSince(lastProbeStartedAt) < 60 AND lastProbeOutcome == .probeSuccess (Plan 09-01)           | VERIFIED   | ConnectivityMonitor.swift:281-285                                                                                                 |
| 3   | runProbe() sets lastProbeStartedAt = Date() at probe START before any await (Plan 09-01)                                                                                    | VERIFIED   | ConnectivityMonitor.swift:288 (placed BEFORE the capture-state block at 290-294, which itself precedes the URLSession await at 302) |
| 4   | runProbe() sets lastProbeOutcome to the EventType just logged AFTER each branch (.probeSuccess, .probeFailure, .silentFailure) (Plan 09-01)                                 | VERIFIED   | ConnectivityMonitor.swift:315 (.probeSuccess), :328 (.probeFailure), :362 (.silentFailure), :374 (.probeFailure)                  |
| 5   | Failures (.probeFailure, .silentFailure) NEVER short-circuit the next probe — outcome filter is .probeSuccess only (D-14) (Plan 09-01)                                      | VERIFIED   | Guard expression at line 283 reads `lastProbeOutcome == .probeSuccess`; failure outcomes are written but never gate suppression   |
| 6   | EventStore.insertEvent calls try modelContext.save() synchronously and is byte-identical to baseline (Plan 09-01)                                                           | VERIFIED   | EventStore.swift:26 (synchronous save); `git diff --stat CellGuard/Services/EventStore.swift` is empty                            |
| 7   | LocationService writes lastBackgroundWakeTimestamp ONLY when UIApplication.shared.applicationState != .active (Plan 09-02)                                                  | VERIFIED   | LocationService.swift:132-137 — conditional write inside the existing @MainActor Task block                                       |
| 8   | LocationService's existing lastActiveTimestamp write semantics are unchanged — gap detection still works (Plan 09-02)                                                       | VERIFIED   | Write-site count = 3 (line 90 startMonitoring, line 123-126 step 4, line 159-162 detectAndLogGap first-launch); detectAndLogGap untouched |
| 9   | HealthDetailSheet renders the wake row inside TimelineView(.periodic(from: .now, by: 1)) (Plan 09-02)                                                                       | VERIFIED   | HealthDetailSheet.swift:110                                                                                                       |
| 10  | HealthDetailSheet uses Date.RelativeFormatStyle to render age (Plan 09-02)                                                                                                  | VERIFIED   | HealthDetailSheet.swift:194-196 (`.relative(presentation: .named, unitsStyle: .abbreviated)`)                                     |
| 11  | When lastBackgroundWakeTimestamp is unset, the row reads "Never (no background wake yet)" (Plan 09-02)                                                                      | VERIFIED   | HealthDetailSheet.swift:192                                                                                                       |
| 12  | The new UserDefaults key is a SEPARATE key from lastActiveTimestamp; literal string `"lastBackgroundWakeTimestamp"` matches across writer (LocationService) and reader (HealthDetailSheet) | VERIFIED   | LocationService.swift:55 declares it; HealthDetailSheet.swift:191 reads the same literal string                                   |
| 13  | DropTimelineChart renders compact inline legend with two color-coded chips: 'Silent' (red), 'Overt' (orange) (Plan 09-03)                                                   | VERIFIED   | DropTimelineChart.swift:252-276 (legendBar) + :281-301 (legendChip with color/label/swatch)                                       |
| 14  | Tapping a chip toggles chartShowSilent / chartShowOvert @AppStorage Bools (Plan 09-03)                                                                                      | VERIFIED   | DropTimelineChart.swift:18 + :22 declarations; lines 254-256 + 257-259 toggle on tap                                              |
| 15  | (i) info button opens a native SwiftUI .popover with Silent/Overt definitions and 'Why this matters' line (Plan 09-03)                                                      | VERIFIED   | DropTimelineChart.swift:260-273 (Button + .popover) + :306-337 (infoPopoverContent body with Drop Types heading, two definitions, Divider, "Why this matters" subhead) |
| 16  | Default state: both chips ON (chartShowSilent = true, chartShowOvert = true) — D-06 (Plan 09-03)                                                                            | VERIFIED   | DropTimelineChart.swift:18 + :22 — both default `= true`                                                                          |
| 17  | When BOTH chips are OFF, the chart shows hint "No series visible — tap a chip to enable" (D-07) (Plan 09-03)                                                                | VERIFIED   | DropTimelineChart.swift:184-191 — middle render branch                                                                            |
| 18  | Toggled-off series are HIDDEN from the chart entirely (filtered from buckets), not dimmed (D-05) (Plan 09-03)                                                               | VERIFIED   | visibleBuckets filter at lines 124-132; Chart(visibleBuckets) at line 193                                                         |
| 19  | dropEvents aggregation and isDropEvent helper are NOT modified — filter affects render path only (Plan 09-03)                                                               | VERIFIED   | `git diff --stat CellGuard/Helpers/DropClassification.swift` is empty; dropEvents still at DropTimelineChart.swift:59 unchanged   |
| 20  | DashboardView's 'Drop Timeline' caption is title-only; legend lives inside chart (single discoverable surface, D-04) (Plan 09-03)                                           | VERIFIED   | DashboardView.swift:39-46 unchanged; no chartShowSilent/chartShowOvert references in DashboardView                                |
| 21  | Chart block has .chartLegend(.hidden) applied so the implicit Swift Charts auto-legend doesn't duplicate the custom chips (Plan 09-03)                                      | VERIFIED   | DropTimelineChart.swift:209 — exactly between .chartForegroundStyleScale and .chartXScale per plan                                |
| 22  | Cross-file UserDefaults key string identity: "lastBackgroundWakeTimestamp" appears verbatim in both files (Plan 09-02)                                                      | VERIFIED   | LocationService.swift:55 + HealthDetailSheet.swift:191 — exact match                                                              |

**Score:** 22/22 static truths verified

ROADMAP Success Criteria mapping:
- SC1 (legend distinguishes silent vs overt) → truths 13, 15, 21 + human test #4
- SC2 (toggle overt off → only silent visible) → truths 14, 16, 17, 18 + human test #5
- SC3 (chart updates within 1s of new event) → truths 6 + human test #7
- SC4 (Last Background Wake ticks live) → truths 7-12, 22 + human tests #2, #3
- SC5 (no two probe entries within same minute, failures never suppressed) → truths 1-5 + human test #1

### Required Artifacts

| Artifact                                            | Expected                                                                              | Status     | Details                                                                                                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CellGuard/Services/ConnectivityMonitor.swift`      | Probe dedup state + guard + 4 outcome assignments                                     | ✓ VERIFIED | All grep checks pass; dedup guard precedes capture block; 1+1+2+1 outcome assignments at four logEvent sites                                                          |
| `CellGuard/Services/LocationService.swift`          | Conditional lastBackgroundWakeTimestamp write inside locationManager(_:didUpdateLocations:) Task | ✓ VERIFIED | UIKit imported; new DefaultsKey constant; conditional write at lines 132-137; 3 lastActiveTimestamp writes preserved; detectAndLogGap untouched                       |
| `CellGuard/Views/HealthDetailSheet.swift`           | TimelineView-wrapped wake row with relative-time tick                                 | ✓ VERIFIED | TimelineView at line 110; lastBackgroundWakeText at lines 190-197; old lastWakeText fully deleted; no Combine timer                                                  |
| `CellGuard/Views/DropTimelineChart.swift`           | Inline chips + popover + AppStorage filter + visibleBuckets render path + chartLegend(.hidden) | ✓ VERIFIED | All required additions present; Chart(visibleBuckets) replaces Chart(buckets); .chartLegend(.hidden) at line 209                                                      |
| `CellGuard/Views/DashboardView.swift`               | Title-only Drop Timeline caption; no chartShow* leak                                  | ✓ VERIFIED | Lines 39-46 unchanged; no @AppStorage("chartShowSilent"|"chartShowOvert") references in this file; @AppStorage("omitLocationData") still present                      |
| `CellGuard/Services/EventStore.swift`               | Byte-identical to baseline (read-only verification per Plan 09-01 contract)           | ✓ VERIFIED | `git diff --stat` empty; try modelContext.save() at line 26 inside insertEvent (also at line 81 inside deleteAllEvents — preexisting)                                 |
| `CellGuard/Helpers/DropClassification.swift`        | Byte-identical to baseline                                                            | ✓ VERIFIED | `git diff --stat` empty; isDropEvent semantics unaltered                                                                                                              |

### Key Link Verification

| From                                                                | To                                                                       | Via                                                                  | Status     | Details                                                                                                                                |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| runProbe() function entry                                           | lastProbeStartedAt + lastProbeOutcome state                              | early-return guard before capturedStatus snapshot                    | ✓ WIRED    | Guard at lines 281-285 sits BEFORE capture block at lines 290-294 (awk sub-range count = 2 references to lastProbeStartedAt as expected) |
| runProbe() do/catch tail                                            | lastProbeOutcome update                                                  | post-logEvent assignment with literal EventType                      | ✓ WIRED    | All four sites carry sibling assignments matching the literal type just logged                                                          |
| LocationService.locationManager(_:didUpdateLocations:)              | UserDefaults set forKey: lastBackgroundWakeTimestamp                     | UIApplication.shared.applicationState != .active gate                | ✓ WIRED    | Conditional write at lines 132-137 sits AFTER the lastActiveTimestamp write per plan ordering                                           |
| HealthDetailSheet TimelineView body                                 | UserDefaults read forKey: lastBackgroundWakeTimestamp                    | lastBackgroundWakeText computed property re-evaluated each tick      | ✓ WIRED    | TimelineView wraps the HStack that consumes lastBackgroundWakeText; computed prop reads UserDefaults fresh each render                  |
| DropTimelineChart legendChip Button(action:)                        | @AppStorage chartShowSilent / chartShowOvert                             | Bool toggle on tap                                                   | ✓ WIRED    | legendChip handler closures call `.toggle()` directly on the AppStorage-backed property                                                  |
| DropTimelineChart Chart body                                        | filtered visibleBuckets                                                  | computed property switching by bucket.type against AppStorage flags  | ✓ WIRED    | visibleBuckets at lines 124-132 feeds Chart(visibleBuckets) at line 193                                                                  |
| DropTimelineChart info Button                                       | .popover(isPresented: $showInfoPopover)                                  | @State Bool toggled by tap                                           | ✓ WIRED    | Button toggles showInfoPopover (line 261); .popover modifier at line 268 binds same state                                               |
| Chart(visibleBuckets) modifier chain                                | implicit Charts legend suppression                                       | .chartLegend(.hidden) modifier                                       | ✓ WIRED    | Modifier present at line 209, between chartForegroundStyleScale and chartXScale per plan                                                |
| EventStore.insertEvent                                              | DashboardView @Query consumers                                           | synchronous modelContext.save() → SwiftData propagation              | ✓ WIRED (static) | EventStore.swift:26 unchanged; DashboardView.swift:11-12 declares @Query — sub-1s propagation requires on-device measurement (human test #7) |

### Data-Flow Trace (Level 4)

| Artifact                          | Data Variable                       | Source                                                               | Produces Real Data | Status      |
| --------------------------------- | ----------------------------------- | -------------------------------------------------------------------- | ------------------ | ----------- |
| HealthDetailSheet wake row        | lastBackgroundWakeText              | UserDefaults.standard.double(forKey: "lastBackgroundWakeTimestamp")   | Yes — written by LocationService when applicationState != .active | ✓ FLOWING  |
| DropTimelineChart Chart           | visibleBuckets                      | buckets → dropEvents → events (passed in via DashboardView allEvents) | Yes — sourced from @Query on ConnectivityEvent SwiftData store    | ✓ FLOWING  |
| DropTimelineChart legendBar chips | chartShowSilent / chartShowOvert    | @AppStorage UserDefaults Bool, default true                           | Yes — toggled by user taps; persisted to UserDefaults               | ✓ FLOWING  |
| ConnectivityMonitor dedup guard   | lastProbeStartedAt / lastProbeOutcome | Set inside runProbe() at probe START (clock) and after each logEvent (outcome) | Yes — populated by every probe execution                | ✓ FLOWING  |
| DashboardView dropCountCards      | allEvents (filtered with isDropEvent) | @Query(sort: \\ConnectivityEvent.timestamp, order: .reverse)         | Yes — SwiftData live query (not modified in this phase, but verified still wired) | ✓ FLOWING  |

### Behavioral Spot-Checks

Skipped — this is a Swift / SwiftUI iOS app. `xcodebuild` and the iOS simulator are not available from the CLI sandbox; no runnable entry points exist outside Xcode. All behavioral verification is delegated to on-device UAT in the `human_verification` section.

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                       | Status                       | Evidence                                                                                                              |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| CHART-01    | 09-03       | Legend distinguishes silent failures from overt path-change drops                                 | ✓ STATIC; ? UAT (test #4)    | legendBar with color-coded chips + .chartLegend(.hidden) suppressing duplicate auto-legend                            |
| CHART-02    | 09-03       | Toggle overt drops off so silent failures stand out                                               | ✓ STATIC; ? UAT (test #5)    | @AppStorage chip flags + visibleBuckets filter (hide-not-dim)                                                         |
| CHART-03    | 09-01       | Home-screen drop count + chart update within 1 second of a silent failure                         | ✓ STATIC; ? UAT (test #7)    | Synchronous EventStore.save() (line 26) + DashboardView @Query (lines 11-12) + probe dedup eliminating .probeSuccess noise |
| POLISH-01   | 09-02       | HealthDetailSheet "Last Background Wake" updates live while the sheet is open                     | ✓ STATIC; ? UAT (tests #2, #3) | TimelineView(.periodic, by: 1s) + applicationState-gated UserDefaults write + Date.RelativeFormatStyle               |
| POLISH-02   | 09-01       | Duplicate probes within the same minute are deduplicated; failures never suppressed               | ✓ STATIC; ? UAT (test #1)    | Sliding 60s window guard with .probeSuccess-only filter (D-12, D-13, D-14); 4 outcome assignments at all logEvent sites |

**Orphaned requirements:** None. REQUIREMENTS.md maps exactly CHART-01, CHART-02, CHART-03, POLISH-01, POLISH-02 to Phase 9 — all five claimed by plans 09-01 through 09-03.

### Anti-Patterns Found

None.

- No TODO / FIXME / XXX / HACK / PLACEHOLDER markers in the five touched files.
- No "placeholder" / "coming soon" / "not yet implemented" copy.
- No calendar-minute-floor logic (D-13 anti-pattern explicitly searched for and absent).
- No `processPendingChanges()`, no `objectWillChange.send()`, no extra `@Observable` scaffolding leaked into EventStore (Plan 09-01 hard prohibition honored).
- No notification observers (`didEnterBackgroundNotification` / `willEnterForegroundNotification`) added to LocationService — direct `applicationState` query was used per plan.
- No Combine `Timer.publish` / `TimerPublisher` in HealthDetailSheet — `TimelineView` is the chosen mechanism per D-09.
- No `chartShow*` AppStorage leak into DashboardView — single discoverable surface (D-04) preserved.
- No third chip type or alternative vocabulary — D-03 (Silent / Overt) lock honored.
- No second filter row — chips ARE the filter (D-04).

### Human Verification Required

Seven items require on-device confirmation. See the `human_verification` block in the frontmatter for the structured list. Summary:

1. **POLISH-02 dedup + failures-never-suppressed** — runtime probe firing during foreground/background cycle and Airplane Mode interruption.
2. **POLISH-01 1 Hz tick** — TimelineView re-render cadence is a SwiftUI runtime behavior.
3. **POLISH-01 background-wake gate** — significant location change while backgrounded must update the timestamp; foreground location callback must NOT.
4. **CHART-01 legend visible + no duplicate auto-legend** — visual confirmation that `.chartLegend(.hidden)` actually suppresses Swift Charts' implicit legend.
5. **CHART-02 filter hides bars + AppStorage persists** — filter behavior plus persistence across cold launch.
6. **CHART-01 popover anchors + copy** — popover anchor behavior and full-text confirmation of the (i) panel.
7. **CHART-03 sub-1s reactivity** — measured end-to-end latency from event log to dashboard update on iPhone 17 Pro Max.

### Gaps Summary

**3 device UAT gaps confirmed by user on iPhone 17 Pro Max (2026-04-26).** Static verification passed all 22 must-haves; the visible defects are runtime layout/sizing failures of what the plans promised.

#### G1 — CHART-01 popover truncates body text (Plan 09-03)

- **Symptom:** "Drop Types" popover clips both Silent/Overt definition rows ("The modem reports it is connected,…" and "NWPathMonitor reported the conne…") AND the "Why this matters" paragraph mid-sentence.
- **Plan promised:** "Popover content explains plain-English definitions plus one short 'Why this matters for the Apple report' line" (D-02). The full text is in the source but never reaches the user.
- **File:** `CellGuard/Views/DropTimelineChart.swift` — popover content + container sizing.
- **Likely fix:** Add `.presentationCompactAdaptation(.popover)` to force popover (not sheet) on compact size class, and a `.frame(idealWidth: 320)` or `.fixedSize(horizontal: false, vertical: true)` on the content VStack so text wraps and the container grows. Verify all four Text elements use `.fixedSize(horizontal: false, vertical: true)`.
- **Severity:** blocking — the popover is the entire mechanism for explaining "Silent" vs "Overt" terminology (D-02).

#### G2 — POLISH-01 "Last Background Wake" row clipped in HealthDetailSheet (Plan 09-02)

- **Symptom:** The wake row text ("Never (no background wake yet)") is cut off at the visible edge of the sheet despite available headroom in the sheet itself. User screenshot 2 shows clear truncation.
- **Plan promised:** Render the wake row with `Date.RelativeFormatStyle` (or "Never (no background wake yet)" when unset). The text exists but can't be read.
- **File:** `CellGuard/Views/HealthDetailSheet.swift` — sheet detent and/or row layout.
- **Likely fix:** Two parts — (a) raise the sheet's detent or switch to `.large` so the bottom row isn't clipped; (b) ensure the wake row's Text uses `.fixedSize(horizontal: false, vertical: true)` and the parent stack doesn't apply `.lineLimit(1)`. Investigate whether the sheet uses `.medium` detent.
- **Severity:** blocking — POLISH-01's whole observable value is the live wake-time row; it must be readable.

#### G3 — Drop Timeline chart axis labels truncated in 6h view (Plan 09-03 polish)

- **Symptom:** In the 6h zoom of the Drop Timeline chart, X-axis time labels are truncated. (24h view shown in screenshot 1 reads cleanly.)
- **Plan promised:** Implicitly readable axis at all three zoom levels (6h / 24h / 7d) per the segmented Picker.
- **File:** `CellGuard/Views/DropTimelineChart.swift` — `.chartXAxis` configuration, lines ~213-228.
- **Likely fix:** For the 6h domain, reduce mark frequency (e.g., `AxisMarks(values: .stride(by: .hour, count: 1))`) or use a shorter format like `.dateTime.hour()` instead of full timestamps. Possibly a per-domain branch so each zoom picks an appropriate stride.
- **Severity:** blocking — 6h view is the highest-density inspection mode and is unreadable.

#### Code review fixes to fold in (advisory but cheap to do during this gap pass)

- **MN-01:** Promote `"lastBackgroundWakeTimestamp"` literal to a shared `enum AppDefaultsKeys`. Touched while G2 work modifies `HealthDetailSheet.swift`.
- **MN-02:** Replace stringly-typed `"Silent"` / `"Overt"` discriminator with `enum DropSeries: String { case silent = "Silent", overt = "Overt" }` across `TimeBucket`, `visibleBuckets`, `chartForegroundStyleScale`, chip labels, and popover content. Touched while G1 + G3 work modifies `DropTimelineChart.swift`.
- These are eligible because the gap-fix plans naturally modify the same files; folding them in costs ~10 extra minutes and removes a class of typo bug. Other review items (MN-03 `@MainActor` annotations on LocationService; MN-04 deterministic stack ordering; NT-* nits) stay deferred — they touch files unrelated to the gap fixes.

#### Items remaining as runtime-only (not gaps)

The other six human-verification items (POLISH-02 dedup behavior, POLISH-01 1 Hz tick, POLISH-01 background-wake gate, CHART-01 no-duplicate auto-legend, CHART-02 filter behavior + AppStorage persistence, CHART-03 sub-1s reactivity) were observable on-device and are not currently flagged as failing. They will need re-confirmation on the rebuilt app after gap closure.

Status is `gaps_found` after device UAT (originally `human_needed` from static verification).

---

_Verified: 2026-04-25_
_Verifier: Claude (gsd-verifier)_
