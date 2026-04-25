---
phase: 08-vpn-context
plan: 01
type: device-verification
status: in-progress
created: 2026-04-25
updated: 2026-04-25
---

# Wave 0 — VPN Detection Mechanism Device Verification

Validates the four assumptions in `08-RESEARCH.md` (lines 127–308) on the
target device before any production code is written. Plans 02–04 do not
start until **Final Decision** below is `GO` or `GO-WITH-WORKAROUND`.

## Setup

- **Device:** iPhone 17 Pro Max
- **iOS version:** _<fill in, e.g. 26.1>_
- **Xcode / Swift toolchain:** _<fill in>_
- **VPN clients tested:** _<e.g. Mullvad 2024.x, WireGuard 1.x, Settings → IKEv2>_
- **Verifier harness location:** _<e.g. Xcode playground attached to device,
  `#if DEBUG` button in CellGuard, scratch file>_
- **Notes on harness:** _<anything notable about how the four checks were run;
  remember to delete or quarantine the scratch verifier before Plan 02>_

## Reference probe (paste into the harness)

```swift
import SystemConfiguration
import Network

private func captureVPNActive() -> Bool {
    guard let cfDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
          let scoped = cfDict["__SCOPED__"] as? [String: Any] else {
        return false
    }
    let prefixes = ["utun", "ipsec", "tap", "tun", "ppp"]
    for key in scoped.keys {
        let lowered = key.lowercased()
        if prefixes.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
    }
    return false
}

// For Check 2 / 4 — print every path update with cellular/wifi/other flags.
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    print("[\(Date())] path=\(path) cellular=\(path.usesInterfaceType(.cellular)) " +
          "wifi=\(path.usesInterfaceType(.wifi)) other=\(path.usesInterfaceType(.other)) " +
          "primary=\(path.availableInterfaces.first?.type as Any)")
}
monitor.start(queue: .main)
```

---

## Check 1 — `CFNetworkCopySystemProxySettings` sees third-party VPN

**Procedure:**
1. Install a third-party VPN (Mullvad / WireGuard / Settings IKEv2 profile).
2. With VPN **OFF**, log all `__SCOPED__` keys.
3. With VPN **ON**, log all `__SCOPED__` keys.
4. Confirm at least one new key with prefix in `{utun, ipsec, ppp, tap, tun}`
   appears only in the VPN-ON list.

### Raw output — VPN OFF

```
<paste the full __SCOPED__ key list here>
```

### Raw output — VPN ON

```
<paste the full __SCOPED__ key list here>
```

### Newly-appeared keys with target prefix

- _<list keys>_

**Verdict — Check 1:** PASS / FAIL  
_(write reason if FAIL)_

---

## Check 2 — `path.usesInterfaceType(.cellular)` under VPN-over-cellular

**Procedure:**
1. Disable Wi-Fi (cellular only).
2. Enable third-party VPN so the tunnel rides cellular.
3. Capture the next `NWPathMonitor` update.

### Raw output

```
cellular = <true|false>
wifi     = <true|false>
other    = <true|false>
primary interface type = <e.g. .other>
```

**Required:** `cellular == true` AND primary interface is `.other`.

**Verdict — Check 2:** PASS / FAIL  
_(write reason if FAIL — broad VPN-04 trigger blocked, escalate)_

---

## Check 3 — iCloud Private Relay false-positive guard

**Procedure:**
1. Disable any third-party VPN.
2. Enable iCloud Private Relay (Settings → Apple ID → iCloud → Private Relay → On).
3. Log all `__SCOPED__` keys.

### Raw output — Private Relay ON, no other VPN

```
<paste the full __SCOPED__ key list here>
```

### Keys with target prefix detected (should be empty)

- _<list keys, or write "none">_

**Verdict — Check 3:** PASS / PASS WITH WORKAROUND / FAIL

**Workaround (only if PASS WITH WORKAROUND):**
- Offending key string: `<exact key>`
- Filter to add in `captureVPNActive()`: _<concrete substring/regex Plan 03 must apply, e.g. exclude keys containing "mask" or matching "<prefix>">_

---

## Check 4 — `NWPathMonitor` fires on VPN up/down transitions

**Procedure:**
1. Start `NWPathMonitor` with the printing handler above.
2. Toggle VPN OFF → ON. Record callback count + timing within first 5s.
3. Toggle VPN ON → OFF. Record callback count + timing within first 5s.

### Raw output — OFF → ON transition

```
<paste callback timestamps + count here>
```

### Raw output — ON → OFF transition

```
<paste callback timestamps + count here>
```

**Required:** ≥1 callback per transition.

**Verdict — Check 4:** PASS / FAIL  
_(if FAIL — live `@Observable currentVPNState` cannot rely solely on path
updates; Plan 03 must add a polling fallback. Escalate before continuing.)_

---

## Final Decision

> Replace one of the lines below.

- `Final Decision: GO`
- `Final Decision: GO-WITH-WORKAROUND` — workaround summary: _<one line>_
- `Final Decision: NO-GO` — reason: _<one line>_

## Cleanup checklist

- [ ] Scratch verifier removed from `CellGuard/` production tree
      (`git status CellGuard/` shows no changes from this plan)
- [ ] Any `#if DEBUG` UI button or scratch file deleted or quarantined
      to a throwaway branch
- [ ] Findings above are reproducible (procedure + harness location are
      written down)

## Hand-off to Plan 02

Once Final Decision is `GO` or `GO-WITH-WORKAROUND`, paste your decision
back into the chat and I will execute Plans 08-02 → 08-03 → 08-04
sequentially.
