---
phase: quick-260628-ope
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - CellGuard/Models/ConnectivityEvent.swift
  - CellGuard/Services/ConnectivityMonitor.swift
  - CellGuard/Views/EventDetailView.swift
autonomous: true
requirements: [THROUGHPUT-01]
user_setup: []

must_haves:
  truths:
    - "Every ~5 min on cellular, after that cycle's reachability probe succeeded, exactly one event carrying a measured throughputKbps is logged."
    - "Samples below 1000 Kbps are logged as .slowThroughput; samples at/above are logged as .probeSuccess that still carries throughputKbps."
    - "throughputKbps renders in EventDetailView as Mbps when present, and flows through the existing JSON export."
    - ".slowThroughput does NOT fire a drop notification and does NOT count as a drop."
    - "Project compiles for the iPhone 17 Pro Max simulator (** BUILD SUCCEEDED **)."
  artifacts:
    - CellGuard/Models/ConnectivityEvent.swift
    - CellGuard/Services/ConnectivityMonitor.swift
    - CellGuard/Views/EventDetailView.swift
  key_links:
    - "runProbe() end -> throughput scheduling gate (every 5th cycle AND capturedInterface == .cellular AND lastProbeOutcome == .probeSuccess) -> measureThroughput()"
    - "measureThroughput() -> logEvent(throughputKbps:) -> ConnectivityEvent init -> EventStore.insertEvent (bypasses the runProbe dedup guard by never routing through runProbe)"
    - "EventType.slowThroughput -> encodingString / displayName exhaustive switches (hard compile gate)"
---

<objective>
Add a low-data cellular download-throughput probe so the "attached but slow" 5G NR-NSA data stall becomes a MEASURED NUMBER in the event log, not a feeling. The current reachability probe fetches a tiny page and only answers "can I reach the internet at all?" — a small GET sails through a bandwidth collapse, so the stall is invisible in the evidence. This plan fetches a fixed 100 KB payload every ~5 minutes (cellular only, only when reachability already succeeded), times the transfer, logs `throughputKbps`, and flags a new `.slowThroughput` event below a tunable threshold.

Purpose: Close the single biggest gap in the user's Apple Feedback evidence — throughput degradation that latency and reachability cannot catch.
Output: A `throughputKbps` field + `.slowThroughput` event type on the model, a throughput measurement piggybacked on the existing 60s probe cycle, a throughput row in the event detail UI, and a green simulator build.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

@CellGuard/Models/ConnectivityEvent.swift
@CellGuard/Services/ConnectivityMonitor.swift
@CellGuard/Views/EventDetailView.swift
@CellGuard/Helpers/DropClassification.swift

# Implementation notes derived from reading the codebase (executor: rely on these, do not re-derive):
# - Mirror `probeLatencyMs` EXACTLY for the new optional Double: stored property, init param `= nil`,
#   CodingKeys case, encodeIfPresent (placed OUTSIDE the omitLocation gate, alongside probeLatencyMs),
#   decodeIfPresent. SwiftData treats a new optional property as a lightweight migration — NO migration code.
# - EventType already uses explicit Int rawValues up to 6 (vpnStateChange). `encodingString` and `displayName`
#   are EXHAUSTIVE switches with no `default` — adding a case without updating them FAILS the build.
#   `fromEncodingString` and `isDropEvent` (DropClassification.swift) both have a `default` branch, so they
#   compile without the new case; `fromEncodingString` still needs the case for correct round-trip decode,
#   and `isDropEvent`'s default correctly classifies `.slowThroughput` as NOT a drop (no edit needed there).
# - `scheduleDropNotification` (~line 949) only fires for `.silentFailure` and `.pathChange`->unsatisfied,
#   so `.slowThroughput` is excluded for free (same as `.vpnStateChange`) — NO edit needed, only confirm.
# - Export is JSON-only (no CSV anywhere in the project) — the encodeIfPresent is the entire export change.
# - The runProbe dedup guard (~line 343) gates only the reachability probe. measureThroughput calls logEvent
#   directly, so its event is ALWAYS written and never suppressed — that satisfies the "bypass dedup" requirement
#   without any new flag. measureThroughput must NOT set lastProbeOutcome/lastProbeStartedAt.
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Add throughputKbps field and .slowThroughput event type to the model</name>
  <files>CellGuard/Models/ConnectivityEvent.swift</files>
  <behavior>
    - A ConnectivityEvent created with no throughput argument has throughputKbps == nil (migration-safe default).
    - EventType.slowThroughput has rawValue 7, encodingString "slowThroughput", displayName "Slow Throughput", and round-trips through fromEncodingString.
    - Encoding an event with throughputKbps == 12345 emits a "throughputKbps" JSON key; encoding nil omits the key. Decoding a file lacking the key yields nil.
  </behavior>
  <action>
    Add EventType case `slowThroughput` with EXPLICIT `= 7` to the enum, placed after `vpnStateChange = 6`, with a one-line "why" comment noting the explicit rawValue is for migration safety (consistent with the existing cases). Add the matching arm `case .slowThroughput: "slowThroughput"` to `encodingString`, the arm `case "slowThroughput": .slowThroughput` to `fromEncodingString`, and `case .slowThroughput: "Slow Throughput"` to `displayName`. Both `encodingString` and `displayName` are exhaustive switches with no default — omitting either arm fails compilation, which is the intended safety net.

    Add an optional stored property `var throughputKbps: Double?` to the model in a new "Active probe results" sibling, documented as: measured cellular download rate in Kbps for throughput-sampling events; nil when no throughput was measured for this event. Mirror `probeLatencyMs` exactly across all four Codable touchpoints: add an `init` parameter `throughputKbps: Double? = nil` (place it next to `probeLatencyMs`), assign it in the initializer body, add a `case throughputKbps` to `CodingKeys`, add `try container.encodeIfPresent(throughputKbps, forKey: .throughputKbps)` in `encode(to:)` immediately after the `probeLatencyMs` encode line (OUTSIDE the `omitLocation` block — throughput is not location data), and add `throughputKbps: try container.decodeIfPresent(Double.self, forKey: .throughputKbps)` to the `self.init(...)` call in `init(from:)`, next to the `probeLatencyMs` decode. Do NOT add migration code — a new optional SwiftData property is a lightweight migration.
  </action>
  <verify>
    <automated>cd /Users/mowehr/code/cellguard && grep -q "case slowThroughput = 7" CellGuard/Models/ConnectivityEvent.swift && grep -q "var throughputKbps: Double?" CellGuard/Models/ConnectivityEvent.swift && grep -q "encodeIfPresent(throughputKbps" CellGuard/Models/ConnectivityEvent.swift && grep -q "Slow Throughput" CellGuard/Models/ConnectivityEvent.swift && echo OK</automated>
  </verify>
  <done>The enum has a `slowThroughput = 7` case wired into encodingString, fromEncodingString, and displayName; the model has a `throughputKbps: Double?` property threaded through init, CodingKeys, encodeIfPresent, and decodeIfPresent mirroring probeLatencyMs.</done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Add the throughput measurement and schedule it on the existing probe cycle</name>
  <files>CellGuard/Services/ConnectivityMonitor.swift</files>
  <behavior>
    - measureThroughput fetches the 100 KB Cloudflare payload, times the wall-clock transfer, and computes throughputKbps = (bytesReceived * 8.0) / 1000.0 / seconds.
    - An elapsed time at/below the 0.001s floor (or a non-200 response, or a thrown error) logs NO event (no divide-by-zero, no spurious failure event).
    - A successful measurement logs exactly one event carrying throughputKbps: .slowThroughput when below the threshold, otherwise .probeSuccess.
    - The measurement runs only on every 5th completed reachability cycle, only when capturedInterface == .cellular, and only when this cycle's reachability outcome was .probeSuccess.
  </behavior>
  <action>
    In the "Probe Properties" section add four members, each with a short "why/tunable" comment: a `throughputProbeURL` constant set to the Cloudflare 100 KB down endpoint (the `__down` endpoint with a 102400-byte query, returning exactly 100 KB with no auth — deterministic for data budgeting; note Cloudflare is already the trusted second probe host in confirmSilentFailure, and ~100 KB times ~12/hr times 24h is approximately 29 MB/day, the agreed budget); a `throughputCycleInterval` Int constant `5` (run the measurement once every Nth 60s reachability cycle, approximately 5 minutes; lower means more samples and more data); a `slowThroughputThresholdKbps` Double constant `1000` (a starting value for a degraded cellular stall worth flagging — 1 Mbps — tunable); and a `private var throughputCycleCounter = 0` to schedule sampling.

    Reuse `makeProbeSession()` (a fresh ephemeral session per measurement, mirroring the reachability probe's stale-socket fix). Add a `@MainActor private func measureThroughput(...)` that takes the pre-await snapshot parameters runProbe already captured (status, interface, isExpensive, isConstrained, lowPowerMode, vpnState, vpnInterface). Inside: create the session with a `defer { session.finishTasksAndInvalidate() }`, record a start Date, `await session.data(for:)` the throughput URL inside a do/catch. On success, guard that the response is HTTP 200 and that elapsed seconds are greater than 0.001 — otherwise return without logging (guard against divide-by-zero and absurdly small elapsed producing a meaningless astronomical rate). Compute kbps from the received byte count, choose the type (`.slowThroughput` when kbps is below `slowThroughputThresholdKbps`, else `.probeSuccess`), and call `logEvent(...)` passing the snapshot through plus the new `throughputKbps:` argument. In the catch branch, return without logging — a throughput fetch failure is not a connectivity failure because this cycle's reachability probe already succeeded, and logging here would create a spurious event. Document with a "why" comment that this method calls logEvent directly (never routes through runProbe) so its event is always written, inherently bypassing the runProbe dedup guard, and that it deliberately does NOT touch lastProbeOutcome / lastProbeStartedAt so it cannot extend the reachability dedup window.

    Add a `throughputKbps: Double? = nil` parameter to `logEvent(...)` next to `probeLatencyMs`, and thread it into the `ConnectivityEvent(...)` initializer call inside logEvent's Task. This is the only change to logEvent.

    At the very END of `runProbe()`, after the do/catch closes, add the scheduling gate: increment `throughputCycleCounter`, then if `throughputCycleCounter % throughputCycleInterval == 0` AND `capturedInterface == .cellular` AND `lastProbeOutcome == .probeSuccess`, `await measureThroughput(...)` passing the already-captured snapshot vars (capturedStatus, capturedInterface, capturedIsExpensive, capturedIsConstrained, capturedLowPowerMode, capturedVPNState, capturedVPNInterface). Add a "why" comment: piggyback on the existing 60s reachability cycle; measure actual download bandwidth only on cellular and only when reachability succeeded this cycle (a connectivity failure is already captured as silentFailure/probeFailure, and Wi-Fi throughput is irrelevant to the cellular-modem evidence); the 60s timer is the dominant caller so this is foreground-driven in practice. Do NOT add any background throughput probing. Keep the VPN-over-cellular case out of scope — gate strictly on `capturedInterface == .cellular` for minimalism; a cycle where the interface reads `.other` simply skips that sample.
  </action>
  <verify>
    <automated>cd /Users/mowehr/code/cellguard && grep -q "func measureThroughput" CellGuard/Services/ConnectivityMonitor.swift && grep -q "__down" CellGuard/Services/ConnectivityMonitor.swift && grep -q "throughputCycleCounter" CellGuard/Services/ConnectivityMonitor.swift && grep -q "slowThroughputThresholdKbps" CellGuard/Services/ConnectivityMonitor.swift && grep -q "throughputKbps" CellGuard/Services/ConnectivityMonitor.swift && echo OK</automated>
  </verify>
  <done>ConnectivityMonitor has the four throughput members, a measureThroughput() that logs exactly one throughput-bearing event (or none on failure/guard), a logEvent throughputKbps parameter, and a scheduling gate at the end of runProbe firing every 5th cellular cycle after a successful reachability probe.</done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Surface throughput in the detail UI, confirm notification exclusion, and build-verify</name>
  <files>CellGuard/Views/EventDetailView.swift</files>
  <behavior>
    - When event.throughputKbps is present, the Cellular section shows a "Throughput" row formatted as Mbps (e.g. 12345 Kbps renders "12.3 Mbps"); when nil, no row appears.
    - .slowThroughput events render their displayName ("Slow Throughput") in the list and detail title with no broken exhaustive switch.
    - The full project compiles for the iPhone 17 Pro Max simulator.
  </behavior>
  <action>
    In `EventDetailView`, inside the existing `Section("Cellular")`, add a conditional `LabeledContent("Throughput", ...)` that appears only when `event.throughputKbps` is non-nil, formatting the value as Mbps by dividing Kbps by 1000 with one decimal (matching the existing `LabeledContent` row style used for Latency). Place it after the Cellular Data Access row.

    Confirm — do NOT edit — that `scheduleDropNotification` excludes `.slowThroughput` (its guard only matches `.silentFailure` and `.pathChange`->unsatisfied, exactly like `.vpnStateChange`) and that `isDropEvent` in DropClassification.swift returns false for `.slowThroughput` via its `default` branch. If either is somehow NOT already the case after Tasks 1-2, fix it; otherwise leave both untouched. No other view needs changes — EventListView uses `event.eventType.displayName` (no exhaustive switch) so the new case renders automatically.

    Then run the build-verify gate (Task 3 is the real compile gate for all three files).
  </action>
  <verify>
    <automated>cd /Users/mowehr/code/cellguard && grep -q "Throughput" CellGuard/Views/EventDetailView.swift && xcodebuild build -project CellGuard.xcodeproj -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -quiet 2>&1 | tee /tmp/cellguard-throughput-build.log | tail -20 && grep -q "BUILD SUCCEEDED" /tmp/cellguard-throughput-build.log && echo VERIFIED</automated>
  </verify>
  <done>EventDetailView shows a Throughput (Mbps) row when present; .slowThroughput is confirmed excluded from drop notifications and drop counts; xcodebuild prints ** BUILD SUCCEEDED ** for the iPhone 17 Pro Max simulator.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| app -> speed.cloudflare.com | Outbound GET for a fixed 100 KB payload; response body is discarded (only byte count + elapsed time are read) |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-ope-01 | Information Disclosure | throughput GET egress | low | accept | Endpoint is an unauthenticated, body-less size endpoint on an already-trusted host (Cloudflare is the existing confirmSilentFailure host). No device/user data is transmitted beyond the request itself; honors the project's no-external-transmission-of-data constraint. |
| T-ope-02 | Denial of Service | data budget / battery | low | mitigate | Cellular-only + every-5th-cycle (~5 min) + 100 KB caps usage at ~30 MB/day; foreground-only (no background throughput probing); fresh ephemeral session per measurement avoids stale-socket hangs. |
| T-ope-03 | Tampering | response payload | low | accept | Only `data.count` and wall-clock elapsed are read; the response body is never parsed or executed, so a tampered/oversized response cannot corrupt state (and the request is HTTPS to a pinned-by-DNS trusted host). |
| T-ope-SC | Tampering | npm/pip/cargo installs | n/a | accept | No new packages — all first-party Apple frameworks (URLSession, Foundation, SwiftData) already in use. |
</threat_model>

<verification>
- `xcodebuild build -project CellGuard.xcodeproj -scheme CellGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'` prints ** BUILD SUCCEEDED **.
- `grep` confirms: `case slowThroughput = 7`, `var throughputKbps: Double?`, `encodeIfPresent(throughputKbps`, `func measureThroughput`, `__down`, `slowThroughputThresholdKbps`, and a `Throughput` row in EventDetailView.
- Runtime throughput behavior (the actual sampling cadence and a real NR-NSA slow sample on device) is device-only and is the user's to verify — out of scope for this build gate.
</verification>

<success_criteria>
- A throughput measurement runs every ~5 min on cellular after a successful reachability probe and logs exactly one event carrying throughputKbps.
- Samples below 1000 Kbps are `.slowThroughput`; at/above are `.probeSuccess` carrying the number; both bypass the reachability dedup (always written).
- `throughputKbps` shows in EventDetailView as Mbps and flows through JSON export via encodeIfPresent.
- `.slowThroughput` fires no drop notification and is not counted as a drop.
- The project compiles for the iPhone 17 Pro Max simulator.
</success_criteria>

<output>
Create `.planning/quick/260628-ope-add-low-data-cellular-throughput-probe-1/260628-ope-SUMMARY.md` when done.
</output>
