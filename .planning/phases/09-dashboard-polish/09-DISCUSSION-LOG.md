# Phase 9: Dashboard Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-25
**Phase:** 09-dashboard-polish
**Areas discussed:** Chart legend & terms, Overt-drop filter UX, Live wake mechanism + scope, Probe deduplication strategy

---

## Chart Legend & Terms (CHART-01)

### Q1: Where and how should the legend explain "silent" vs "overt"?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline legend below chart | Color swatches with one-line plain-English captions visible at all times. No taps needed. | |
| Compact legend + info button | Color swatches inline; an (i) button opens a popover with full definitions. Less visual weight; one tap for context. | ✓ |
| Native Chart legend only | Keep what Swift Charts auto-generates; add a small footnote caption with definitions instead of a structured legend. | |

**User's choice:** Compact legend + info button.

### Q2: What labels should the chart use?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent / Overt | Keep current terminology — accurate, matches REQUIREMENTS.md. | ✓ |
| Silent failure / Path drop | More self-explanatory but longer; "Path drop" aligns with NWPathMonitor vocabulary. | |
| Silent / Network | Friendlier "Network" replacement for "Overt" but loses precise "path-change" meaning. | |

**User's choice:** Silent / Overt.

### Q3: How should the (i) info popover render?

| Option | Description | Selected |
|--------|-------------|----------|
| Native .popover | SwiftUI .popover anchored to the (i) button. Lightweight, dismisses on tap-outside. | ✓ |
| Sheet (.sheet medium detent) | More room for definitions and "Why this matters" framing. More taps to dismiss. | |
| Inline disclosure | DisclosureGroup that expands in-place. Costs vertical real estate. | |

**User's choice:** Native .popover.

---

## Overt-Drop Filter UX (CHART-02)

### Q1: What control should let the user filter overt drops?

| Option | Description | Selected |
|--------|-------------|----------|
| Two legend chips (tap to toggle) | Legend swatches ARE the filter. Single touch target, matches Apple Health/Fitness chart legends. | ✓ |
| Segmented picker above chart | Three-way: All / Silent only / Overt only. Mutually exclusive, very explicit, but adds a row above the existing time-window picker. | |
| Single 'Show overt drops' toggle | One Toggle in chart header; binary only. Matches CHART-02 wording most literally but can't isolate Overt. | |

**User's choice:** Two legend chips (tap to toggle).

### Q2: Default state on first open?

| Option | Description | Selected |
|--------|-------------|----------|
| Both Silent and Overt visible | Most truthful default; matches today's behavior. | ✓ |
| Silent only by default | Hides overt out of the box; user opts in to see overt drops. Reduces noise but may surprise. | |

**User's choice:** Both visible.

### Q3: Should the filter state persist?

| Option | Description | Selected |
|--------|-------------|----------|
| @AppStorage | Persists across launches via UserDefaults. Same pattern as omitLocation. | ✓ |
| Per-session only (@State) | Resets on every launch. Simpler but annoying for daily users. | |

**User's choice:** @AppStorage.

**Notes (locked without re-asking):** Toggling a chip OFF hides that series from render (does not just dim). If both chips end up off, chart shows "No series visible — tap a chip" hint instead of an empty plot.

---

## Live Wake Mechanism + Scope (POLISH-01)

### Q1: What should "Last Background Wake" actually count?

| Option | Description | Selected |
|--------|-------------|----------|
| True background wakes only | Track a separate timestamp written ONLY when the app was woken from background. Most accurate, most useful diagnostic. | ✓ |
| Any wake or callback (current behavior) | Keep using lastActiveTimestamp — every location callback counts. Simplest, but the label is misleading. | |
| Show both | Two rows: "Last Activity" and "Last Background Wake". More information density. | |

**User's choice:** True background wakes only.
**User notes:** "explain the difference between the two and why recommend only true background wakes" — Claude provided full rationale mid-discussion (preserved in conversation history): the diagnostic question the sheet exists to answer is "is iOS still waking me when backgrounded?", and the current behavior conflates that with foreground location updates, making the field unactionable during real-world use.

### Q2: How should the sheet refresh while open?

| Option | Description | Selected |
|--------|-------------|----------|
| TimelineView(.periodic 1s) | SwiftUI re-renders only the timestamp subview every second. Idiomatic, no Combine/Timer lifecycle. | ✓ |
| @Observable on MonitoringHealthService | Single source of truth via observable property. Still needs TimelineView for relative-time live ticking. | |
| Timer.publish + @State | Combine 1s timer in the sheet. More boilerplate; Combine in maintenance mode per project conventions. | |

**User's choice:** TimelineView(.periodic 1s).

### Q3: Format for the live timestamp?

| Option | Description | Selected |
|--------|-------------|----------|
| Relative time | "12s ago", "3m 14s ago". Live ticking is visually obvious. | ✓ |
| Absolute time | "HH:MM:SS" — clear but doesn't tick visually. | |
| Both | "14:32:11 (3m 14s ago)" — most informative, takes more horizontal space. | |

**User's choice:** Relative time.

---

## Probe Deduplication (POLISH-02)

### Q1: Where should deduplication happen?

| Option | Description | Selected |
|--------|-------------|----------|
| At probe-firing layer | runProbe()/runSingleProbe() check "last probe started <60s ago?" and short-circuit. Saves the network round-trip too. | ✓ |
| At log layer (collapse on write) | Probes always run; logEvent detects duplicate-within-minute and skips/merges. More overhead, less testable. | |
| Hybrid | Firing-layer for probeSuccess; log-layer for nothing. (Equivalent to firing-layer if failures don't dedupe.) | |

**User's choice:** At probe-firing layer.

### Q2: Should probe failures dedupe the same way?

| Option | Description | Selected |
|--------|-------------|----------|
| No — always log every failure | Failures are the entire evidence stream. Even two failures 10s apart both belong in the log. | ✓ |
| Yes — dedupe failures too | Strictest reading of POLISH-02. Loses evidence resolution. | |
| Dedupe failures only if outcome+interface+VPN identical | Smarter dedup; might be over-engineered for the volume. | |

**User's choice:** No — always log every failure.

### Q3: What's the dedup window?

| Option | Description | Selected |
|--------|-------------|----------|
| Sliding 60 seconds | "<60s since last probe" — no boundary edge case at minute changes. | ✓ |
| Same calendar minute | Floor both timestamps to the minute. Matches POLISH-02 wording literally but boundary-fiddly. | |
| Sliding 30 seconds | Tighter dedup; only suppresses launch-during-timer edge case. | |

**User's choice:** Sliding 60 seconds.

### Q4 (clarification): How should the firing-layer guard interact with prior probe outcome?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip only if prior probe succeeded | Track lastProbeStartedAt AND lastProbeOutcome. Skip second probe only when (within 60s) AND (last result was probeSuccess). If prior was failure, allow second probe. | ✓ |
| Hard 60s skip regardless of outcome | Skip any probe within 60s, even if last failed. Acceptable risk: next timer probe is at most 60s away. | |
| Run all probes; dedupe at log layer instead | Move dedup to logEvent; failures always pass through. Trades network cost for absolute-fresh diagnostic data. | |

**User's choice:** Skip only if prior probe succeeded.

---

## Claude's Discretion

- CHART-03 mechanism (Query reactivity vs explicit refresh trigger) — investigate during research/planning, pick the lowest-blast-radius option that passes the 1-second criterion.
- Background-wake detection mechanism (UIApplication.shared.applicationState query vs explicit isBackground flag set by lifecycle notifications) — planner picks; semantics are equivalent.
- Popover copy for (i) button — exact wording of Silent/Overt definitions and "Why this matters" line.
- Legend chip "off" state visual treatment (greyed swatch, strikethrough, opacity, etc.) — match Apple HIG.

## Deferred Ideas

- Live "VPN: connecting" pill on the dashboard (flagged in Phase 8 CONTEXT.md, not folded in here).
- detectAndLogGap migration to lastBackgroundWakeTimestamp (revisit during Phase 10 if REPORT-01 surfaces accuracy issues).
- Per-series chart subtitle showing counts (could land in Phase 10's analytics surface).
- Chart accessibility audit (VoiceOver) — v1.4 polish.
- BGAppRefreshTask handler also writing lastBackgroundWakeTimestamp when that path gets utilized.
