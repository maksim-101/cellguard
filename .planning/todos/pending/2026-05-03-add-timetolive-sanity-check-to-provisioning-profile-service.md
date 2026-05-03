---
created: 2026-05-03T06:19:10Z
title: Add TimeToLive sanity check to ProvisioningProfileService
area: services
files:
  - CellGuard/Services/ProvisioningProfileService.swift
---

## Problem

`ProvisioningProfileService` currently parses the embedded provisioning profile and reads `ExpirationDate`, but does not inspect the `TimeToLive` field. When Xcode / Apple's signing servers occasionally issue a 7-day profile despite a paid Developer Program membership (a known Xcode failure mode that has bitten this project before), the user has no visible indication: the displayed `ExpirationDate` is still ~7 days in the future, which looks normal at a glance.

The previous incident on 2026-04-26 → 2026-05-03 was ultimately diagnosed as cert revocation (during work on the unrelated Dicticus app), but the same symptom — silent app death after exactly 7 days — also matches a 7-day-TTL profile, and there is no way for the user to distinguish the two failure modes without manually inspecting the embedded profile via `security cms -D`.

A loud, visible warning would catch the 7-day-TTL case the moment the app is launched after a build, instead of after a week of degraded service.

## Solution

1. Extend the `ProvisioningProfile` Decodable struct in `ProvisioningProfileService.swift` to decode the `TimeToLive` field (Int, days).
2. Expose a computed property `isShortTTL: Bool` that returns true when `TimeToLive < 30`.
3. In `HealthDetailSheet.swift` (or wherever the provisioning profile expiry is rendered), surface a yellow/red warning banner when `isShortTTL` is true, with text along the lines of: "Provisioning profile was issued with a {N}-day lifetime instead of the expected 365 days. The app will stop launching on {expiry date}. Rebuild from Xcode to renew."
4. Optionally: also schedule an additional notification when `isShortTTL` is true, separate from the existing 7-days-before-expiry notification.

Reference for diagnostics commands and cert/profile background: `~/.claude/notes/ios-codesigning.md`.

Trivial scope, ~1 hour. Prophylactic — would have caught the 2026-04-26 incident immediately.
