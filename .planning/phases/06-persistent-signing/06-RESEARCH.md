# Phase 6: Persistent Signing - Research

**Researched:** 2026-04-20
**Domain:** iOS code signing, provisioning profile management, local notifications
**Confidence:** HIGH

## Summary

Phase 6 switches CellGuard from free personal-team signing (7-day expiry) to the paid Apple Developer Program (Team VTWHBCCP36), then adapts `ProvisioningProfileService` and its notification logic to match the new 1-year certificate lifecycle.

The critical finding is that the Xcode project already has `DEVELOPMENT_TEAM = VTWHBCCP36` and `CODE_SIGN_STYLE = Automatic` in both Debug and Release build configurations in `project.pbxproj`. There is no "Personal Team" override anywhere in the project. This means the **signing migration in Xcode is effectively complete** — the project will automatically provision with the paid team on the next Xcode build against a registered device. No pbxproj edits are needed.

The work for this phase is therefore concentrated entirely in Swift code: three targeted changes to `ProvisioningProfileService` (update `isExpiringSoon` threshold, update `scheduleExpiryNotification` to warn 7 days out, update notification copy), plus a corresponding display update in `HealthDetailSheet`.

**Primary recommendation:** Treat Phase 6 as a pure Swift code update to `ProvisioningProfileService` and `HealthDetailSheet`. Verify the Xcode project builds cleanly with the paid team before writing Swift changes, then make four targeted edits.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SIGN-01 | App is signed with paid Apple Developer team (Team ID VTWHBCCP36) instead of free personal team | DEVELOPMENT_TEAM = VTWHBCCP36 already in pbxproj. Automatic signing handles profile provisioning. Verify in Xcode Signing & Capabilities tab. |
| SIGN-02 | App remains installed on device indefinitely without requiring re-deployment every 7 days | Paid developer provisioning profiles are valid for up to 1 year (tied to Developer Program membership). No code change needed — result of SIGN-01. |
| EXPR-01 | ProvisioningProfileService detects the 1-year distribution certificate expiry date | Existing `loadProfile()` already reads ExpirationDate from embedded.mobileprovision. The ExpirationDate value in the plist will simply be ~1 year out instead of ~7 days. No parsing change needed — only threshold/copy changes. |
| EXPR-02 | User receives a local notification 7 days before certificate expiry | Update `scheduleExpiryNotification()`: change 48-hour offset to 7-day offset, update notification copy from "48 hours" to "7 days", update notification body to reflect re-deployment is not imminent urgency. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Code signing configuration | Xcode project / build system | — | Signing identity and team live in pbxproj, managed by Xcode Automatic signing |
| Provisioning profile expiry detection | App service layer (ProvisioningProfileService) | — | Reads embedded.mobileprovision from app bundle at runtime; no server needed |
| Expiry warning notification | App service layer (ProvisioningProfileService) | iOS notification system (UNUserNotificationCenter) | Schedules a local UNNotificationRequest; no server push infrastructure |
| Expiry date display | UI layer (HealthDetailSheet) | — | Already reads from profileService.expirationDisplayText and isExpiringSoon |

## Standard Stack

### Core (already in project — no new dependencies needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| UserNotifications (`UNUserNotificationCenter`) | iOS 10+ (stable) | Schedule 7-day-before-expiry local notification | First-party framework, already imported in ProvisioningProfileService |
| Foundation (`PropertyListDecoder`) | iOS 2+ (stable) | Parse plist from mobileprovision binary container | Already used in existing loadProfile() |
| SwiftUI (`@Observable`) | iOS 17+ | Reactive state for HealthDetailSheet | Already used |

No new libraries or dependencies are required for this phase. [VERIFIED: codebase grep]

## Architecture Patterns

### System Architecture Diagram

```
[Xcode Build] --> [embedded.mobileprovision bundled into .app]
                                |
                                v
[App launch / .onAppear] --> [ProvisioningProfileService.loadProfile()]
                                |
                   +------------+------------+
                   |                         |
                   v                         v
        [expirationDate stored]    [scheduleExpiryNotification()]
                   |                         |
                   v                         v
        [HealthDetailSheet]      [UNTimeIntervalNotificationTrigger]
        shows expiry date        fires 7 days before expiry
        and isExpiringSoon       delivers local notification
        badge
```

### Recommended Project Structure

No structural changes. All changes are within existing files:

```
CellGuard/
├── Services/
│   └── ProvisioningProfileService.swift  ← 3 targeted edits
├── Views/
│   └── HealthDetailSheet.swift           ← display label update (isExpiringSoon threshold context)
└── CellGuard.xcodeproj/
    └── project.pbxproj                   ← already correct, verify only
```

### Pattern 1: Existing mobileprovision Parse (unchanged)

**What:** Binary CMS/PKCS#7 container with embedded plist XML. Extract XML by locating `<?xml` and `</plist>` markers, decode with PropertyListDecoder.

**Why unchanged:** The paid team provisioning profile has the same binary format and the same `ExpirationDate` plist key. Only the value changes (~1 year instead of ~7 days). [VERIFIED: codebase read + confirmed by multiple sources on mobileprovision format]

```swift
// Source: existing ProvisioningProfileService.swift (no change needed)
let profile = try decoder.decode(ProvisioningProfile.self, from: plistData)
expirationDate = profile.expirationDate  // Now ~1 year out
```

### Pattern 2: isExpiringSoon Threshold Update

**What:** Change the 48-hour warning threshold to 7 days to match the paid certificate lifecycle. A 7-day warning gives the developer enough time to re-deploy before the app stops launching.

**Current code:**
```swift
var isExpiringSoon: Bool {
    guard let expirationDate else { return false }
    return expirationDate.timeIntervalSinceNow < 48 * 3600  // 48 hours
}
```

**Updated code:**
```swift
var isExpiringSoon: Bool {
    guard let expirationDate else { return false }
    return expirationDate.timeIntervalSinceNow < 7 * 24 * 3600  // 7 days
}
```

[ASSUMED] 7 days is the appropriate warning window for a 1-year certificate. The project decisions memo states EXPR-02 requires notification 7 days before expiry, so this aligns.

### Pattern 3: Notification Scheduling Update

**What:** Shift the notification trigger from 48 hours before expiry to 7 days before expiry. Update the notification body copy to remove the urgent "re-sign in Xcode" framing and replace with a calmer annual reminder.

**Current code (to replace):**
```swift
let warningDate = expirationDate.addingTimeInterval(-48 * 3600)
content.title = "CellGuard Profile Expiring"
content.body = "Your provisioning profile expires in 48 hours. Re-sign the app in Xcode to continue monitoring."
```

**Updated code:**
```swift
let warningDate = expirationDate.addingTimeInterval(-7 * 24 * 3600)
content.title = "CellGuard Certificate Expiring"
content.body = "Your Developer certificate expires in 7 days. Deploy the app from Xcode to renew it and continue monitoring."
```

`UNTimeIntervalNotificationTrigger` handles intervals up to the pending notification limit (64 max). A single non-repeating notification at 7 * 24 * 3600 seconds (604,800 seconds) has no documented maximum limit and will work correctly. [VERIFIED: Apple developer forums + UNTimeIntervalNotificationTrigger docs]

### Pattern 4: HealthDetailSheet Display Update

**What:** The existing `isExpiringSoon` badge in `HealthDetailSheet` already uses `profileService.isExpiringSoon` and `profileService.expirationDisplayText`. Because `isExpiringSoon` now evaluates to 7 days instead of 48 hours, the red/bold badge will appear 7 days before expiry automatically with no UI code changes needed.

However, the "Profile Expires:" label may warrant a context update in the footer — consider renaming to "Cert Expires:" to reflect the paid-team language shift. This is a cosmetic one-line change.

```swift
// Current in HealthDetailSheet.swift line 96:
Text("Profile Expires:")
// Could update to:
Text("Cert Expires:")
```

[ASSUMED] This label rename is cosmetic and optional. The planner can decide whether to include it.

### Anti-Patterns to Avoid

- **Don't use UNCalendarNotificationTrigger with year-ahead date:** Use `UNTimeIntervalNotificationTrigger` as the existing code does. Simpler and already working.
- **Don't reschedule the notification on every app foreground:** The existing pattern schedules once on `loadProfile()`, called only from `.onAppear`. This is correct — rescheduling on every foreground would accumulate duplicate pending notifications.
- **Don't hardcode "Personal Team" removal:** The pbxproj already has the paid team ID. There is no personal team string to remove.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Certificate expiry detection | Custom CMS/PKCS#7 parser | Existing plist-in-ASCII extraction (already in codebase) | The current approach works for both free and paid profiles — format is identical |
| Notification scheduling | Custom timer or BGTask for expiry check | UNTimeIntervalNotificationTrigger (already in codebase) | OS delivers the notification even if the app is not running |

## Common Pitfalls

### Pitfall 1: Simulator Has No embedded.mobileprovision

**What goes wrong:** `loadProfile()` returns nil on Simulator — all expiry fields show "Unknown (Simulator)". Developer assumes the code is broken.

**Why it happens:** The Simulator does not embed a provisioning profile in the .app bundle because no actual device-level signing happens during Simulator builds.

**How to avoid:** The existing code already guards against this with a nil-check on `Bundle.main.path(forResource: "embedded", ofType: "mobileprovision")`. No change needed. Test on real device only for EXPR-01 validation. [VERIFIED: codebase read + confirmed by Apple developer forums]

**Warning signs:** `profileService.expirationDate == nil` and `profileService.expirationDisplayText == "Unknown (Simulator)"` on Simulator. Expected behavior.

### Pitfall 2: Notification Fires Immediately If Already Past Warning Window

**What goes wrong:** If the app is first launched when the certificate has fewer than 7 days remaining, `warningDate > Date()` is false and no notification is scheduled. The existing code already handles this:

```swift
guard warningDate > Date() else { return }
```

**How to avoid:** No change needed. This guard is already correct.

### Pitfall 3: Xcode May Show "No Account" or Wrong Team After Opening

**What goes wrong:** When opening the project on a Mac that hasn't authenticated the paid Apple ID, Xcode shows the signing identity as "unknown" or "no account" even though `DEVELOPMENT_TEAM = VTWHBCCP36` is in pbxproj.

**How to avoid:** Sign in to Xcode with the Apple ID associated with the paid team (VTWHBCCP36) via Xcode > Settings > Accounts before building. Xcode Automatic signing will then download and create the correct provisioning profile automatically. [VERIFIED: Apple developer documentation on automatic signing]

**Warning signs:** Build error "No profiles for 'com.moritz.cellguard.app' were found."

### Pitfall 4: PPQ Check on First Launch

**What goes wrong:** For teams created after June 6, 2021, iOS checks `https://ppq.apple.com` on the first launch of a development or ad-hoc signed app. If the device is offline on first launch, the app may fail to open.

**Why it matters:** This is a system-level behavior introduced by Apple for paid development team profiles.

**How to avoid:** Ensure the device is online when running the app for the first time after deploying the new paid-team signed build. Subsequent launches work offline. [CITED: https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/]

**Warning signs:** App shows "Unable to run" on first launch without network.

### Pitfall 5: Old "profileExpiry" Notification Not Cancelled

**What goes wrong:** If the free-team notification was already scheduled with the 48-hour window, it will fire even after re-deployment with the paid team.

**How to avoid:** The existing code calls `center.removePendingNotificationRequests(withIdentifiers: ["profileExpiry"])` before re-scheduling. This already cleans up the old notification. No change needed.

## Code Examples

Verified patterns from existing codebase and official sources:

### Updated scheduleExpiryNotification (full method)

```swift
// Source: existing ProvisioningProfileService.swift — modified for 7-day window
private func scheduleExpiryNotification() {
    guard let expirationDate else { return }

    let center = UNUserNotificationCenter.current()

    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        guard granted, error == nil else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["profileExpiry"])

        // Calculate 7 days before expiration
        let warningDate = expirationDate.addingTimeInterval(-7 * 24 * 3600)

        guard warningDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "CellGuard Certificate Expiring"
        content.body = "Your Developer certificate expires in 7 days. Deploy the app from Xcode to renew it and continue monitoring."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(warningDate.timeIntervalSinceNow, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "profileExpiry",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Failed to schedule profile expiry notification: \(error)")
            }
        }
    }
}
```

### Updated isExpiringSoon property

```swift
// Source: existing ProvisioningProfileService.swift — threshold changed to 7 days
var isExpiringSoon: Bool {
    guard let expirationDate else { return false }
    return expirationDate.timeIntervalSinceNow < 7 * 24 * 3600
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 48-hour expiry warning (free team 7-day cycle) | 7-day expiry warning (paid team 1-year cycle) | Phase 6 | Notification timing and copy update |
| Free personal team (7-day provisioning profile) | Paid developer team VTWHBCCP36 (1-year profile) | Phase 6 | App persists on device without re-deployment |

## Runtime State Inventory

This phase does not rename any identifiers, rebrand strings, or migrate data models. It is a signing configuration change and threshold update in Swift code.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | No stored data references signing team or certificate expiry | None |
| Live service config | No external service configuration references team ID or profile | None |
| OS-registered state | One pending UNNotificationRequest with identifier "profileExpiry" | Automatically replaced by new scheduleExpiryNotification() call on next launch |
| Secrets/env vars | No secrets reference signing team ID | None |
| Build artifacts | Xcode derived data / .xcarchive from old free-team build | Delete DerivedData before first paid-team build to avoid stale artifacts |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 7 days is the correct warning window for isExpiringSoon threshold | Standard Stack / Code Examples | Low — EXPR-02 explicitly states 7-day notification; isExpiringSoon threshold should match for UI consistency |
| A2 | "Cert Expires:" label rename in HealthDetailSheet is optional/cosmetic | Architecture Patterns | Low — purely cosmetic, no functional impact |
| A3 | The PPQ online check applies to this project's paid team builds (post June 2021) | Common Pitfalls | Medium — if team was created before June 6 2021, PPQ check may not apply |

## Open Questions (RESOLVED)

1. **Is the paid Apple Developer account (VTWHBCCP36) actively enrolled and paid?**
   - What we know: Team ID is already in pbxproj, suggesting it was set intentionally
   - What's unclear: Whether the Developer Program membership is current/active
   - Recommendation: Verify at developer.apple.com before deploying; expired membership = no profile issuance
   - RESOLVED: Handled by human-verify checkpoint (Task 2) — developer confirms Xcode shows team with no signing errors before proceeding.

2. **What provisioning profile type will Xcode generate with automatic signing?**
   - What we know: For direct device deployment (not App Store), Xcode with paid team generates a development provisioning profile (not distribution). Development profiles expire in 1 year.
   - What's unclear: The ROADMAP says "distribution certificate expiry" — for Xcode direct deployment, the profile is technically a development profile, not a distribution profile. The embedded certificate is a Development certificate, not a Distribution certificate.
   - Recommendation: Clarify in plan whether the 1-year expiry target refers to development profile expiry (Xcode deployment) or an ad-hoc/distribution profile. For personal device use via Xcode, development profile is correct. The functional result (1-year expiry) is the same either way.
   - RESOLVED: For Xcode direct deployment, Xcode generates a development provisioning profile (1-year expiry). The plan uses "Developer certificate" language which is accurate. The functional result (1-year expiry) is identical regardless of profile type.

## Environment Availability

Step 2.6: SKIPPED — this phase requires Xcode (always available on dev machine for an iOS project) and network access to ppq.apple.com for first launch on device. No new tools or services are introduced.

## Validation Architecture

`nyquist_validation` is explicitly `false` in `.planning/config.json`. Validation section omitted.

## Security Domain

`security_enforcement` not explicitly set in config — treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — local app, no user auth |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | No | No user-controlled input in this phase |
| V6 Cryptography | No | Provisioning profile is read-only; crypto handled by iOS code signing |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Notification content leakage | Information disclosure | Notification body contains no sensitive data — only expiry timing |
| Notification spoofing | Tampering | UNUserNotificationCenter local notifications cannot be spoofed from outside the app |

No new security concerns introduced by this phase. The mobileprovision file is read-only and the notification contains no PII.

## Sources

### Primary (HIGH confidence)
- Codebase: `CellGuard/Services/ProvisioningProfileService.swift` — existing implementation verified by direct read
- Codebase: `CellGuard.xcodeproj/project.pbxproj` — DEVELOPMENT_TEAM = VTWHBCCP36 confirmed in both Debug and Release configs
- [Apple Developer: Compare Memberships](https://developer.apple.com/support/compare-memberships/) — free vs paid profile expiry differences

### Secondary (MEDIUM confidence)
- [Apple Developer: Provisioning Profile Updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/) — PPQ check behavior documented
- [Apple Developer Forums: Paid account provisioning expiry](https://developer.apple.com/forums/thread/70282) — 1-year validity for paid account profiles
- [UNTimeIntervalNotificationTrigger docs](https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger) — no maximum time interval documented for non-repeating notifications

### Tertiary (LOW confidence)
- [Chris Mash: Knowing when provisioning profile expires](https://chris-mash.medium.com/knowing-when-your-ios-apps-provisioning-profile-is-going-to-expire-4689d03d0d5) — confirms mobileprovision parsing approach

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all verified in existing codebase
- Architecture: HIGH — changes are isolated to two existing files with well-understood patterns
- Pitfalls: HIGH — simulator limitation and PPQ check are well-documented; others verified in codebase
- Signing migration: HIGH — DEVELOPMENT_TEAM already set; only requires Xcode re-provision on next build

**Research date:** 2026-04-20
**Valid until:** 2026-07-20 (stable domain — iOS code signing APIs and provisioning profile format are stable)
