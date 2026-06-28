---
quick_id: 260628-rpt
type: execute
wave: 1
depends_on: []
files_modified:
  - CellGuard/Helpers/HealthScore.swift
  - CellGuard/Views/DashboardView.swift
  - CellGuard/Views/DropTimelineChart.swift
  - CellGuard/Views/AnalyticsView.swift
autonomous: true
requirements:
  - 260628-rpt (Option H "Cellular Health" home redesign with dynamic score system)

must_haves:
  truths:
    - "Home screen shows two ScoreRings (Overall, Last 24h) computed from cellular probe outcomes, with Wi-Fi excluded."
    - "A verdict pill compares last-24h health against overall and is hidden when either score is unavailable."
    - "24h failure-mode breakdown (Silent, Overt, Stall, Degraded) and a probes/drops/degraded count row appear on the home screen."
    - "The Drop Timeline chart distinguishes Stall (purple) drops from Silent (red) and Overt (orange)."
    - "Analytics shows a Drop Timeline section and a Data Stalls Key Driver fact when stalls exist."
  artifacts:
    - CellGuard/Helpers/HealthScore.swift
  key_links:
    - "HealthScore cellular-probe discriminator (isExpensive == true) drives every score, count, and verdict."
    - "DropSeries.stall maps severeThroughput events into the timeline and the chart color scale."
---

<objective>
Rebuild the CellGuard home screen as Option H "Cellular Health": a dynamic score system that
grades cellular link quality from probe outcomes (Wi-Fi excluded, VPN tolerant), plus a 24h
failure-mode breakdown and a usual-vs-now verdict. Extend the Drop Timeline + Analytics to
surface the new Stall (severe throughput) failure mode.

Purpose: Replace raw drop-count cards with an at-a-glance, interpretable health grade that
makes the "attached but unreachable" and "data stall" failure modes legible for the Apple report.

Output: One new pure-computation helper (HealthScore.swift) and faithful UI rewrites of
DashboardView, DropTimelineChart, and AnalyticsView. NO @Model schema change → NO SwiftData migration.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@CLAUDE.md
@CellGuard/Models/ConnectivityEvent.swift
@CellGuard/Helpers/DropClassification.swift
@CellGuard/Views/DashboardView.swift
@CellGuard/Views/AnalyticsView.swift
@CellGuard/Views/DropTimelineChart.swift
@CellGuard/Helpers/MockData.swift

Key facts established by the reads:
- EventType cases: pathChange=0, silentFailure=1, probeSuccess=2, probeFailure=3,
  connectivityRestored=4, monitoringGap=5, vpnStateChange=6, slowThroughput=7, severeThroughput=8.
- ConnectivityEvent fields used here: `eventType: EventType`, `isExpensive: Bool`,
  `probeLatencyMs: Double?`, `throughputKbps: Double?`, `timestamp: Date`, `radioTechnology: String?`.
- `isDropEvent(_:)` (DropClassification.swift) is already cellular-gated; reuse it, do not reinvent.
- New .swift files auto-include via the project's PBXFileSystemSynchronizedRootGroup — no pbxproj edit.
- Match the existing SwiftUI idioms: cards use `Color(.secondarySystemBackground)` +
  `RoundedRectangle(cornerRadius: 10)`; section captions use `.font(.caption).foregroundStyle(.secondary)`.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: HealthScore.swift — pure score/verdict/failure-count computation</name>
  <files>CellGuard/Helpers/HealthScore.swift</files>
  <behavior>
    - score returns nil when fewer than minCellularProbesForScore (10) cellular probes are in the window.
    - score = 100 when every cellular probe is a clean probeSuccess; 0 when none are clean.
    - A probe-outcome event with isExpensive == false (Wi-Fi) is NOT counted as a cellular probe.
    - band(for:) returns "Good"/.green at 80, "Fair"/.yellow at 60, "Poor"/.orange at 40,
      "Bad"/orange-red at 20, "Critical"/.red below 20.
    - verdict returns nil if either score is nil; returns "Typical"/equal/.secondary when scores are equal;
      "Much better than usual" when last24h exceeds overall by >= 10; "Much worse than usual" when it
      trails by >= 10.
    - failureCounts.drops == silent + overt + stall; probes == cellular-probe count in the window.
  </behavior>
  <action>
Create a caseless enum `HealthScore` (import SwiftUI for Color, import Foundation). Keep it pure and
synchronous — no async, no SwiftData, no I/O. Comments explain WHY, especially the
isExpensive=cellular rationale (NWPath marks the cellular interface expensive; on Wi-Fi the same probe
runs but isExpensive is false, so isExpensive is the Wi-Fi-excluding, VPN-tolerant cellular
discriminator — a VPN tunnel does not flip isExpensive off the way it can confuse interfaceType).

Named tunable static constants: `slowLatencyThresholdMs: Double = 3000` and
`minCellularProbesForScore = 10`.

Define the probe-outcome set as the EventTypes {.probeSuccess, .probeFailure, .silentFailure,
.slowThroughput, .severeThroughput}. A CELLULAR PROBE is a probe-outcome event whose `isExpensive`
is true. A CLEAN probe is a cellular probe whose `eventType == .probeSuccess` and
`(probeLatencyMs ?? 0) <= slowLatencyThresholdMs` (clean is a strict subset of cellular probes, so it
is counted by filtering the cellular-probe set — never the raw events).

`static func score(events: [ConnectivityEvent], since: Date?) -> Double?`: filter events to the window
(`since.map { d in events.filter { $0.timestamp >= d } } ?? events`); let `probes` = cellular probes
in the window, `clean` = the clean subset; return nil when `probes.count < minCellularProbesForScore`,
otherwise `100 * Double(clean.count) / Double(probes.count)`.

`static func band(for score: Double) -> (label: String, color: Color)` using the thresholds:
>= 80 ("Good", .green); 60..<80 ("Fair", .yellow); 40..<60 ("Poor", .orange);
20..<40 ("Bad", Color(red: 1, green: 0.42, blue: 0.13)); else ("Critical", .red).

`static func verdict(last24h: Double?, overall: Double?) -> (text: String, symbol: String, color: Color)?`:
return nil if either argument is nil. Otherwise let Δ = last24h - overall and return, as an ordered
high-to-low cascade so there are no gaps between bands:
Δ >= 10 → ("Much better than usual", "arrow.up.to.line", .green);
Δ >= 4 → ("Better than usual", "arrow.up", .green);
Δ >= -3 → ("Typical", "equal", .secondary);   // the design's >= -3 && < 4 band
Δ > -10 → ("Worse than usual", "arrow.down", .orange);
else → ("Much worse than usual", "arrow.down.to.line", .red).
The symbol strings are SF Symbol names. Comment WHY the cascade ordering removes the boundary gap that
the literal per-band ranges leave between -4 and -3.

Add `struct FailureCounts { let silent, overt, stall, degraded, drops, probes: Int }` and
`static func failureCounts(events: [ConnectivityEvent], since: Date?) -> FailureCounts` over the same
window filter:
- silent  = count of (eventType == .silentFailure && isExpensive);
- overt   = count of (eventType == .pathChange && isDropEvent(e))  // reuse isDropEvent, already cellular-gated;
- stall   = count of (eventType == .severeThroughput && isExpensive);
- degraded = count of (eventType == .slowThroughput && isExpensive)
             + count of (eventType == .probeSuccess && isExpensive && (probeLatencyMs ?? 0) > slowLatencyThresholdMs);
- drops   = silent + overt + stall;
- probes  = cellular-probe count in the window.

Add a convenience for the 24h window boundary: `static func since24h() -> Date { Date().addingTimeInterval(-86400) }`.
Do NOT inline 86400 elsewhere — call this.
  </action>
  <verify>
    <automated>xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3</automated>
  </verify>
  <done>HealthScore.swift compiles; build ends in ** BUILD SUCCEEDED **. score/band/verdict/failureCounts/since24h all present with the exact thresholds and the isExpensive cellular discriminator; no schema change.</done>
</task>

<task type="auto">
  <name>Task 2: DashboardView.swift — Option H layout + ScoreRing</name>
  <files>CellGuard/Views/DashboardView.swift</files>
  <action>
KEEP exactly as-is: the `healthBar` and its health helpers, the three NavigationLinks (View All Events
with the `\(allEvents.count)` count badge, Summary Report, Location Analytics), the omit-data Toggle,
the Export ShareLink, `navigationTitle`/`navigationBarTitleDisplayMode`, the `.sheet` presenting
HealthDetailSheet, and the `allEvents` @Query / @State / @AppStorage declarations.

REMOVE from `body` and DELETE the now-unused private helpers: `connectivityStateCard`,
`dropCountCards`, `dropStatCard`, `lastDropRow`, and the entire "Drop Timeline" VStack that uses
`DropTimelineChart`. (DropTimelineChart now lives only inside AnalyticsView per Task 3.) Remove the
`import Charts` line if nothing else in the file references Charts after deletion.

INSERT, in `body` after `healthBar` and before the "View All Events" NavigationLink, three cards. All
three derive from HealthScore over `allEvents`. Compute once at the top of `body` (or in small private
computed vars): overall = `HealthScore.score(events: allEvents, since: nil)`,
last24h = `HealthScore.score(events: allEvents, since: HealthScore.since24h())`,
counts24h = `HealthScore.failureCounts(events: allEvents, since: HealthScore.since24h())`,
verdict = `HealthScore.verdict(last24h: last24h, overall: overall)`.

Card 1 — "Cellular Health" card (standard card chrome: `Color(.secondarySystemBackground)`,
`RoundedRectangle(cornerRadius: 10)`, `.padding(.horizontal)`):
  - Title `Text("Cellular Health").font(.headline)` with caption `Text("Wi-Fi excluded").font(.caption).foregroundStyle(.secondary)`.
  - Two side-by-side `ScoreRing`s in an HStack: left labeled "Overall" bound to `overall`,
    right labeled "Last 24h" bound to `last24h`.
  - Below the rings, centered, a verdict pill: a `Label(verdict.text, systemImage: verdict.symbol)`
    tinted `verdict.color`, wrapped in a `Capsule().fill(verdict.color.opacity(0.15))` background with
    horizontal/vertical padding. HIDE the pill entirely when `verdict == nil`.

Card 2 — probe-count row (`Color(.secondarySystemBackground)`, cornerRadius 10): an HStack with
`Text("Last 24 h").foregroundStyle(.secondary)` on the left and, on the right, a single line built from
counts24h: "{probes} probes · {drops} drops · {degraded} degraded", where the `{drops}` number renders
in `.red` and the `{degraded}` number renders in `.yellow` (use concatenated `Text` runs with
`.foregroundStyle` so only the numbers are colored; the "probes/drops/degraded" words and separators
stay default). Use `counts24h.probes`, `counts24h.drops`, `counts24h.degraded`.

Card 3 — failure-mode card with four LabeledContent-style rows using counts24h. Each row: a colored dot
(`Circle().fill(color).frame(width: 8, height: 8)`) + name + a `.caption .secondary` subtitle, with the
trailing count bolded. Rows:
  - red dot, "Silent", subtitle "unreachable", value `counts24h.silent`;
  - orange dot, "Overt", subtitle "system loss", value `counts24h.overt`;
  - purple dot (`Color(.systemPurple)`), "Stall", subtitle "data dead", value `counts24h.stall`;
  - yellow dot, "Degraded", subtitle "slow, not a drop", value `counts24h.degraded`.
Use a small private row helper to avoid repetition.

Add a reusable `ScoreRing` view (a `private struct ScoreRing: View` in this file). Inputs: a `score: Double?`
and a `label: String`. Render a ZStack: a track `Circle().stroke(Color(.systemGray5), lineWidth: ~10)`,
and when score is non-nil an overlaid `Circle().trim(from: 0, to: score/100).stroke(band.color, style: StrokeStyle(lineWidth: ~10, lineCap: .round)).rotationEffect(.degrees(-90))` where
`band = HealthScore.band(for: score)`. Center the integer score (`Text("\(Int(score.rounded()))").font(.title.bold())`)
with the band word (`Text(band.label).font(.caption2).foregroundStyle(.secondary)`) below it. When score
is nil, draw only the track and center a big `Text("—").font(.title.bold())` with `Text("No data").font(.caption2).foregroundStyle(.secondary)` below. Put the `label` ("Overall"/"Last 24h") under the ring as a
`.caption .secondary`. Give the ring a fixed frame (~88pt) so the two rings sit evenly.

Match existing spacing: cards get `.padding(.horizontal)` and `.padding(.bottom, 6)` like the rows they
replace. Do NOT introduce code comments except where a WHY is non-obvious.
  </action>
  <verify>
    <automated>xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3</automated>
  </verify>
  <done>Build ends in ** BUILD SUCCEEDED **. Home body shows healthBar → Cellular Health card (two ScoreRings + conditional verdict pill) → 24h probe-count row → failure-mode card → the unchanged NavigationLinks/Toggle/Export. connectivityStateCard, dropCountCards, dropStatCard, lastDropRow, and the Drop Timeline VStack are gone, with no orphaned helper or unused import.</done>
</task>

<task type="auto">
  <name>Task 3: DropTimelineChart + AnalyticsView — Stall series & Data Stalls fact</name>
  <files>CellGuard/Views/DropTimelineChart.swift, CellGuard/Views/AnalyticsView.swift</files>
  <action>
DropTimelineChart.swift:
  - Add `case stall = "Stall"` to the `DropSeries` enum.
  - In `buckets`, replace the line `let type: DropSeries = (event.eventType == .silentFailure) ? .silent : .overt`
    with a switch on `event.eventType`: `.silentFailure → .silent`, `.severeThroughput → .stall`,
    default → `.overt`.
  - Add `@AppStorage("chartShowStall") private var chartShowStall: Bool = true` alongside the existing
    chartShowSilent/chartShowOvert flags (default true, persisted — same pattern/justification as siblings).
  - In `visibleBuckets`, add a `.stall: return chartShowStall` arm to the switch.
  - In `legendBar`, add a third `legendChip(label: DropSeries.stall.rawValue, color: Color(.systemPurple), isOn: chartShowStall) { chartShowStall.toggle() }` after the Overt chip.
  - In `chartForegroundStyleScale`, add `DropSeries.stall.rawValue: Color(.systemPurple)` so the scale is
    [silent: .red, overt: .orange, stall: Color(.systemPurple)].
  - In `infoPopoverContent`, add a third color block (purple dot) with title `DropSeries.stall.rawValue`
    and body "Reachable, but data throughput is effectively dead — the 5G NR-NSA data stall." mirroring the
    existing Silent/Overt blocks.
  - Use `Color(.systemPurple)` everywhere to match the app's purple (consistent with Task 2's Stall dot).
  Note: the "both series off" edge-case hint currently checks `!chartShowSilent && !chartShowOvert`;
  extend it to also require `!chartShowStall` so the "No series visible" hint only shows when ALL three
  are off.

AnalyticsView.swift:
  - Add a "Drop Timeline" `Section` near the top of the `List`, BEFORE the "Key Drivers" section (place it
    after the `probeLatencySection` block inside the `if !dropEvents.isEmpty` branch, or as its own leading
    section), embedding `DropTimelineChart(events: events)`. Give it a header `Text("Drop Timeline")`.
  - In `insightFacts`, immediately AFTER the Silent Failures fact append (when stall count > 0) a Data
    Stalls fact: compute `stallCount = dropEvents.filter { $0.eventType == .severeThroughput }.count`,
    `stallPct = Double(stallCount) / Double(dropEvents.count) * 100`, and append
    `("bolt.horizontal.circle", "Data Stalls (of total drops)", String(format: "%.0f%%", stallPct))` only
    when `stallCount > 0`. Keep all existing facts (NRNSA, Peak Hour) and their order intact.
  </action>
  <verify>
    <automated>xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3</automated>
  </verify>
  <done>Build ends in ** BUILD SUCCEEDED **. Timeline renders severeThroughput events as a purple "Stall" series with a third legend chip + popover entry; the chart color scale maps stall→systemPurple. Analytics shows a Drop Timeline section above Key Drivers and a Data Stalls fact (after Silent Failures) when stalls exist; existing facts unchanged.</done>
</task>

</tasks>

<verification>
- After each task, `xcodebuild -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO build` ends in ** BUILD SUCCEEDED **.
- No @Model edits → no SwiftData migration introduced (grep ConnectivityEvent.swift is untouched).
- HealthScore is the single source of every score/count/verdict on the home screen; DropTimelineChart is
  referenced only from AnalyticsView after Task 2.
- Optional visual confirmation (not a gate): launch the simulator build with `--seed-mock-data` and screenshot
  the home + Analytics to confirm rings, verdict pill, and the purple Stall bars render with the seeded data.
</verification>

<success_criteria>
- Three sequential tasks complete with a green build at each gate.
- Home screen matches Option H: Cellular Health card (Overall + Last 24h ScoreRings, conditional verdict
  pill), 24h probe-count row (drops red, degraded yellow), four-row failure-mode card.
- Stall (severe throughput) failure mode is visible in the timeline (purple) and Analytics (Data Stalls fact).
- Removed Dashboard helpers leave no dead code; no design questions reopened.
</success_criteria>

<output>
Create `.planning/quick/260628-rpt-option-h-cellular-health-home-redesign-w/260628-rpt-SUMMARY.md` when done.
</output>
