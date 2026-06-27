---
quick_id: 260627-rtr
title: Explicit VPN status in event detail + self-check explanation in UI
status: ready
branch: feature/apple-support-script
---

# Quick Task 260627-rtr: Explicit VPN status + self-check explanation

Two small UI changes for evidence rigor. Build via xcodebuild MCP (iOS Simulator, iPhone 17 Pro). Atomic commits. Do NOT push. Verify branch is feature/apple-support-script first.

## Task 1 — Always show VPN status in EventDetailView (CellGuard/Views/EventDetailView.swift)
- Currently the "VPN" section (lines ~39-48) renders ONLY when vpnState is an active state (not disconnected/invalid), so events captured with no VPN show nothing — ambiguous for an evidence tool (absence could mean "no VPN" OR "not captured").
- Change: ALWAYS render the VPN section when `event.vpnState != nil` (i.e. VPN state was captured at all). Show:
  - "State" row = `state.displayName` (so "Disconnected" is shown explicitly, not hidden).
  - "Interface" row = `event.vpnInterface ?? "None"` (always show it so a disconnected event reads "Interface: None" rather than omitting it).
- Keep it hidden ONLY for truly-legacy events where `vpnState == nil` (pre-Phase-8 events that never captured VPN state) — those genuinely have no data.
- Result: a no-VPN event clearly reads State: Disconnected / Interface: None; an active event reads State: Connected / Interface: utun3.
- verify: build succeeds; disconnected events now show the VPN section explicitly.

## Task 2 — Explain the VPN detection self-check in the UI (CellGuard/Views/HealthDetailSheet.swift)
- The "Run VPN Detection Self-Check" button (line ~99) currently has no explanation, and the result alert just shows the raw scan string.
- Add an explanatory caption directly under the button (match the existing caption style used for the other diagnostic blocks in this view — `.font(.caption).foregroundStyle(.secondary)`), explaining:
  - What it does: "Verifies that CellGuard can actually see an active VPN tunnel on this device and iOS version. Connect a VPN first, then tap to confirm detection works before trusting VPN-tagged data."
  - The three possible outcomes and what each means:
    - "Matched (e.g. utun3): VPN tunnel detected — VPN tagging is reliable."
    - "No match: proxy settings exist but no VPN tunnel was recognized — detection may be blind to this VPN."
    - "No proxy settings: no VPN tunnel active. Expected when no VPN is connected; a problem if a VPN IS connected."
- Also append a short interpretation line to the result alert/sheet so the on-tap result is self-explanatory (e.g. prefix the existing result string with a one-line plain-language verdict). Keep the raw key list in the result too.
- Keep the existing once-per-launch os_log self-check and the shared detectVPNInterface() core unchanged.
- verify: build succeeds; button has a visible explanation + outcome legend; result alert includes a plain-language verdict.

## Build & commit
- Build via xcodebuild MCP (iOS Simulator, iPhone 17 Pro) → BUILD SUCCEEDED.
- One atomic commit per task (code only). Do NOT push. Do NOT commit .planning/ docs (orchestrator handles).
