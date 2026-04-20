---
status: partial
phase: 07-wifi-context
source: [07-VERIFICATION.md]
started: 2026-04-20T21:30:00Z
updated: 2026-04-20T21:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. SSID populated on Wi-Fi
expected: Launch app on Wi-Fi, wait for a connectivity event, open event detail view. Wi-Fi section appears with the correct SSID of the connected network.
result: [pending]

### 2. No Wi-Fi section on cellular
expected: Disable Wi-Fi, trigger a connectivity event, open event detail view. No Wi-Fi section appears (section hidden entirely).
result: [pending]

### 3. JSON export includes wifiSSID (privacy OFF)
expected: Export JSON with privacy toggle OFF, inspect file. wifiSSID field present in event JSON objects for events logged while on Wi-Fi.
result: [pending]

### 4. JSON export omits wifiSSID (privacy ON)
expected: Export JSON with privacy toggle ON, inspect file. wifiSSID field absent from ALL event JSON objects.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
