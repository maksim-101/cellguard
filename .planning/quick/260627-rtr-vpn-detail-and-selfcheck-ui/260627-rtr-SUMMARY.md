---
quick_id: 260627-rtr
title: Explicit VPN status in event detail + self-check explanation in UI
status: complete
branch: feature/apple-support-script
completed: 2026-06-27
---

# Quick Task 260627-rtr Summary

## Task 1 — Always show VPN status in EventDetailView

**File:** `CellGuard/Views/EventDetailView.swift`

**Change:** Removed the `state != .disconnected && state != .invalid` guard from the VPN section condition. The section now renders for any event where `vpnState != nil` (i.e., VPN state was captured at all). Both `State` and `Interface` rows are always shown — `Interface` falls back to `"None"` when `vpnInterface` is nil. Legacy events with `vpnState == nil` continue to show no VPN section.

**Result:** A no-VPN event explicitly reads `State: Disconnected / Interface: None`, eliminating the ambiguity between "no VPN" and "not captured."

**Commit:** `dc7dd04`

---

## Task 2 — Explain VPN detection self-check in HealthDetailSheet

**File:** `CellGuard/Views/HealthDetailSheet.swift`

**Changes:**
- Wrapped the self-check button in a `VStack` containing an explanatory caption and a three-outcome legend, both styled `.font(.caption).foregroundStyle(.secondary)` to match existing diagnostic blocks.
- Added `vpnSelfCheckVerdict` computed property that translates the raw scan result string (`matched=...`, `NO MATCH — keys=[...]`, `no proxy settings`) into a plain-language verdict sentence.
- Alert message now reads: `[verdict]\n\nRaw: [raw result]`.

**Commit:** `a92552e`

---

## Build Result

**BUILD SUCCEEDED** — iOS Simulator, iPhone 17 Pro, Debug-iphonesimulator.

## Deviations

None — plan executed exactly as written.
