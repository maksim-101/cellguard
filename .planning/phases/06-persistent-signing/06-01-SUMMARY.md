---
phase: 06-persistent-signing
plan: 01
status: complete
started: 2026-04-20
completed: 2026-04-20
duration: ~3min
---

# Summary: Persistent Signing Code Changes

## What Was Built

Updated ProvisioningProfileService and HealthDetailSheet to complete the transition from free personal team (7-day re-sign cycle) to paid Apple Developer Program (1-year certificate).

## Changes Made

1. **ProvisioningProfileService.swift** — Replaced 48-hour expiry threshold with 7-day window; updated notification copy to reference "Developer certificate" instead of "provisioning profile"; updated class doc comment to reflect paid team signing (Team VTWHBCCP36)
2. **HealthDetailSheet.swift** — Renamed "Profile Expires:" label to "Cert Expires:"

## Key Files

- `CellGuard/Services/ProvisioningProfileService.swift` — 7-day threshold + notification copy
- `CellGuard/Views/HealthDetailSheet.swift` — Updated expiry label

## Verification

- Automated: All grep checks pass (7*24*3600 x2, Certificate Expiring x1, Cert Expires x1, zero 48*3600, zero "Profile Expires:")
- Human: App builds with Team VTWHBCCP36, installs and runs on iPhone 17 Pro Max, "Cert Expires:" label visible in Health Detail sheet

## Self-Check: PASSED

All must_haves verified. No deviations from plan.
