---
status: partial
phase: 05-privacy-aware-export
source: [05-VERIFICATION.md]
started: 2026-03-26T18:16:00Z
updated: 2026-03-26T18:16:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Toggle visible above Export button in running app
expected: "Omit location data" toggle appears immediately above the "Export Event Log (JSON)" ShareLink button, styled consistently with the surrounding action rows (rounded rectangle, secondary background).
result: [pending]

### 2. Export with toggle ON produces location-free JSON
expected: No event object in the exported JSON contains `latitude`, `longitude`, or `locationAccuracy` keys.
result: [pending]

### 3. Toggle state survives app relaunch
expected: After enabling the toggle, force-quitting, and relaunching, the toggle is still in the ON position.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
