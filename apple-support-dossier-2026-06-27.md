# iPhone 17 Pro Max — Persistent Cellular Data-Stall: Reference Dossier

**Prepared:** 2026-06-27 · **Owner:** (device owner) · **Purpose:** Reference guide for escalating to senior Apple support and for an Apple Feedback Assistant report.

> This dossier consolidates the full history, the diagnostic evidence, the elimination logic, and the open questions for a persistent cellular connectivity defect on an iPhone 17 Pro Max running iOS 26.x. It is written to be handed to a senior Apple advisor / engineering.

---

## 1. Executive Summary

An **iPhone 17 Pro Max on iOS 26.x** exhibits a persistent **"attached but unreachable" cellular data stall**: the OS reports a healthy connection (full bars, 5G, network path `satisfied`) while **no data actually flows** — fresh connections to multiple independent internet hosts time out. The condition typically clears only after toggling Airplane Mode.

Through systematic elimination across **3 device units, 3 SIMs, 2 carriers, 2 countries, with and without VPN, and with and without a restored backup**, every external variable has been ruled out. **The only remaining constant is the iPhone 17 Pro Max hardware/firmware running iOS 26** — pointing to a **systemic iOS 26 / baseband software regression in the 5G NR-NSA data path**, not a defect of any single unit, SIM, or carrier.

A custom diagnostic app (**CellGuard**) was built to capture timestamped, two-host-confirmed evidence of each failure, suitable for correlation against Apple's baseband logs (sysdiagnose).

---

## 2. Device & Account

| Item | Detail |
|---|---|
| Device | iPhone 17 Pro Max |
| OS | iOS 26.x (latest point release installed) |
| Current unit | Second warranty replacement — **set up fresh, NOT restored from a backup** (signed into Apple ID only) |
| Prior unit | First warranty replacement — set up from a backup |
| Original unit | Exhibited the same defect |
| SIMs tried | Physical SIM, home eSIM, and a German travel eSIM (while traveling) — **all affected** |
| Carrier | Home carrier (confirmed, twice, that they have no comparable reports from other customers) |

---

## 3. The Failure Signature

The defect is a **silent modem failure** — what the project terms "attached but unreachable":

- **`NWPathMonitor` reports `status = .satisfied`** on the **cellular** interface — the OS believes the internet is reachable.
- **Signal indicators show full bars and 5G**, radio access technology **`NRNSA`** (5G Non-Standalone).
- **Yet active probes to multiple independent hosts time out** (~10 s) — no data transits.
- The OS / CommCenter is **unaware** the data plane is dead, so apps do not fail gracefully (they hang/spin).
- Recovery typically requires **toggling Airplane Mode** (forces baseband re-registration) or a reboot.

**Representative captured event (2026-06-27, 19:55):** Type *Silent Failure*; Path Status *Satisfied*; Interface *Cellular*; Radio Tech **NRNSA**; Probe Latency **10015 ms**; Failure Reason *"The request timed out."* — confirmed against **two independent hosts** (Apple's captive endpoint **and** Cloudflare), with **no VPN active**.

---

## 4. Timeline of Events

- **Ongoing:** Persistent cellular data drops on the iPhone 17 Pro Max — the original reason this investigation began.
- **Device replacements:** Original unit → first replacement (set up from backup) → **second/current replacement (set up fresh, no backup)**. The defect reproduced on **every** unit.
- **SIM variations:** Physical SIM and home eSIM both affected. **While traveling in Germany, a German travel eSIM (different carrier, different country) exhibited the same failures.**
- **Carrier engagement:** Two calls to the home carrier; they report **no similar complaints** from other customers and find nothing wrong account-side.
- **This week — Apple Support:** Calls on **Tuesday and Thursday**. On Thursday the senior advisor suggested removing the two installed VPN profiles (**Proton VPN** and **Tailscale**), noting (paraphrased) that **"iOS 26 became more strict."**
- **VPN removal:** Both VPN apps **deleted**, profiles removed, and a full **Reset Network Settings** performed.
- **Verification with CellGuard:** App reinstalled; monitoring enabled; **silent failures continued with no VPN present** → VPNs ruled out as the cause.
- **2026-06-27 — diagnostic hardening:** Identified and fixed a measurement artifact in the app (stale-socket false positives), and added two-host confirmation so every logged silent failure is corroborated by two independent hosts. Began a controlled baseline data-collection run.

---

## 5. The Elimination Grid (why it is the device/OS)

Every external variable has been varied while the failure persisted:

| Variable | Varied across | Outcome |
|---|---|---|
| **Device unit** | 3 physical units | Reproduces on all |
| **SIM** | Physical SIM, home eSIM, German travel eSIM | Reproduces on all |
| **Carrier** | Home carrier + a German network | Reproduces on both |
| **Country / cell towers** | Home country + Germany | Reproduces in both |
| **VPN** | Present (Proton, Tailscale) and fully removed | Reproduces either way |
| **Restored backup** | First replacement from backup; current set up **fresh** | Reproduces either way (rules out carried-over corrupt config) |
| **Carrier-side fault** | Carrier confirms no other customer reports | Not a network outage |

**Conclusion:** With carrier, SIM, region, towers, VPN, individual unit, and backup-carryover all eliminated, **the only constant is the iPhone 17 Pro Max + iOS 26.** This matches the known pattern where warranty-replacement units reproduce a defect → a **systemic firmware/OS issue**, not a unit fault.

---

## 6. Primary Hypothesis & Open Questions

**Primary hypothesis:** A **software/baseband regression in iOS 26's 5G NR-NSA data-path handling** on the iPhone 17 Pro Max. The modem completes radio registration on NR-NSA (full bars / 5G shown) but **fails to maintain/initialize IP packet forwarding**, and the failure is not reported up to the OS.

**Open questions the remaining tests will answer:**
1. **Is it specific to NR-NSA?** → Test by forcing **Settings → Cellular → Voice & Data → 5G Auto (or LTE)**. If failures drop sharply on LTE but persist on NR-NSA, the defect is localized to the NR-NSA stack — a precise, actionable finding.
2. **Does a newer OS fix it?** → iOS 27 (see §8) as a deliberate, sequenced test after baseline evidence is captured.
3. **Device firmware vs. carrier NSA configuration?** → On-device data alone cannot fully separate these; however, the **cross-carrier / cross-country reproduction (German eSIM)** already makes a carrier-specific cause highly unlikely. Final separation is for Apple engineering via sysdiagnose/baseband-log correlation.

---

## 7. CellGuard — Evidence Methodology (what it proves, and its limits)

**CellGuard** is a purpose-built iOS diagnostic app that logs every cellular connectivity event locally (no cloud, privacy-preserving).

**How it detects a real failure ("divergence"):** it combines **passive** OS signals (`NWPathMonitor` path status, `CoreTelephony` radio access technology) with an **active** probe. A *Silent Failure* is logged **only when**: the path is `satisfied`, the interface is effectively cellular, **and two independent hosts (Apple's captive-portal endpoint and Cloudflare) both fail** on **fresh (ephemeral) connections**. This two-host + fresh-socket design eliminates false positives from stale connections or single-host outages — so each logged failure is trustworthy evidence of a genuine data-plane blackhole.

**Per-event metadata captured:** local + UTC timestamp, event type, path status, interface, radio access technology (e.g. NRNSA), probe latency, failure reason, VPN state + interface, cellular-data-access restriction (when determinable), coarse location, and drop duration. Exportable as CSV/JSON.

**What the evidence proves:** that at specific timestamps the device was **registered on 5G NR-NSA with a `satisfied` path yet zero end-to-end connectivity across two independent hosts** — the mathematical fingerprint of a silent baseband/data-plane stall the OS did not detect.

**Honest limits (state these to Apple, to avoid overclaiming):**
- On-device APIs **cannot read raw baseband state** (RSRP/RSRQ/PCI/RRC) — those are sandboxed. The proof is the *divergence*, not the radio internals.
- A connectivity logger **cannot, by itself, distinguish a device firmware stall from carrier-side congestion** on a given tower — *but* the cross-carrier/cross-country reproduction already rules carrier-specific causes out here.
- **Carrier name** is unavailable (Apple deprecated `CTCarrier` in iOS 16.4); **Cellular-data-restriction state** is often `unknown` (a flaky Apple API). Neither limits the core evidence.

**The decisive correlation for engineering:** match the **exact ISO-8601 timestamp** of a CellGuard *Silent Failure* against the **CommCenter / baseband trace** inside a **sysdiagnose** captured immediately after that failure. That ties the app-level timeout to the baseband state (e.g. PDP/PDU deactivation, RRC issue, network reject code) at that instant.

---

## 8. iOS 27 — Should You Test It?

**Current state (per third-party reporting as of late June 2026 — verify against Apple's live pages before acting):**
- **iOS 27** was announced at WWDC 2026 and is in **early Developer Beta** (Beta 2). Public beta expected **~July 2026**; public release expected **~September 2026**.
- iOS 27 beta release notes **do not explicitly list** a cellular / baseband / NR-NSA fix. (Apple rarely details modem fixes in high-level notes — they ship quietly via modem-firmware + carrier-settings updates.)
- iPhone 17 beta-user cellular reports are **mixed** — some report improved handoffs, others new early-beta regressions (dropped signal, SOS). Beta noise makes it hard to attribute any change to a real fix.
- **iOS 26 context:** the "attached but no data" silent-stall regression is **widely reported** on iOS 26 (notably after **iOS 26.5**); **iOS 26.5.1** reportedly targeted the iPhone 17 series but community reports say the stall persists for many; **iOS 26.6** is in beta. Apple has **not** publicly acknowledged it as a systemic defect. The "iOS 26 is not Apple's best work" sentiment is widely shared.

**Recommendation: do NOT join the iOS 27 *developer* beta as your test right now.** Early dev betas add their own cellular instability (obscuring whether the iOS 26 issue is actually fixed), and downgrading off a beta is a painful full wipe. Better options, in order:
1. **Try the `iOS 26.6` beta** (if willing to run beta) — same major version, lower risk, may already carry a quiet baseband fix.
2. **Wait for the iOS 27 *public* beta (~July 2026)** — a more stable baseline than the dev beta.
3. Meanwhile on iOS 26, keep the **5G Auto / LTE workaround** + Airplane-Mode recovery while you finish collecting evidence.

**Decision framework (independent of the research):**
- **For:** baseband firmware ships with iOS; a major version is the most likely vehicle for a fix; it is a direct test of the software-regression hypothesis.
- **Against:** early betas are unstable (can *worsen* cellular/battery on a daily-driver phone); **downgrading off a beta is painful and near one-way** (DFU wipe; cannot restore a backup made on the newer OS); switching now **changes the variable mid-evidence-collection**.
- **Recommended sequencing:** finish the iOS 26 baseline + the 5G Auto/LTE test first (bank the evidence and the "before" snapshot), **then** test a newer OS — preferably the **public beta or `.0` release** rather than an early developer beta if daily reliability matters.

---

## 9. What to Ask Apple For (Escalation & Remediation)

This has two tracks — **(A) get it escalated to engineering** and **(C) claim the remediation you're owed** after repeated failed replacements. Run both. **(B)** is the evidence that makes (A) stick.

> Not legal advice — researched general guidance. The legal demand differs by **where you bought the phone** (see C). A free consultation with the **Stiftung für Konsumentenschutz (SKS)** is worth it.

### A. Escalation ladder (get to engineering)

1. **Tier 1 (frontline):** don't explain baseband here — they can't act on it. Tick their script (restart, reset network settings — already done), then **ask to be transferred to a Senior Advisor.**
2. **Senior Advisor (Tier 2):** your gateway to engineering. Get their **direct extension/email** and ask them to open an **engineering / technical-assistance ticket** referencing your evidence. Engineering only engages if the advisor attaches: (i) passing hardware diagnostics, (ii) a **sysdiagnose timed to a failure**, (iii) proof the **carrier checked their side** and the SIM/eSIM was changed — all of which you have or can get.
3. **Customer Relations:** request transfer here once you cite **multiple replacements without resolution**. They can authorize refunds/buybacks, out-of-warranty swaps, and model changes (overriding standard policy).
4. **Executive Relations:** if phone support stalls, email a concise, structured note to **tcook@apple.com** — it's monitored by the Executive Relations team, who have override authority and assign a dedicated liaison.

> Internal names (CAS case ID, "RTA" ticket, CS codes, "three replacements → buyback") are **commonly reported community knowledge, not official policy** — use them as orientation, not as quotes you rely on.

### B. The engineering evidence that makes a ticket "stick"

- **Feedback Assistant report** → file at `feedbackassistant.apple.com` to get an **FB number**; this routes straight to engineering. Give the **FB# to your Senior Advisor** so they link it to your support case. (Template in §12.)
- **Sysdiagnose timed to a failure** — the single most important artifact. The baseband log is a **ring buffer that overwrites in ~30–60 s**, so capture it **within seconds** of a Silent Failure:
  1. Install Apple's **Baseband/Cellular logging profile** from `developer.apple.com/bug-reporting/profiles-and-logs/` (expires in ~1–3 weeks — keep one active).
  2. The instant CellGuard logs (or you observe) a stall, press **Volume Up + Volume Down + Side** together for ~**1.25–1.5 s** until you feel a haptic pulse (don't hold past ~3 s → that triggers SOS).
  3. Retrieve it later at **Settings → Privacy & Security → Analytics & Improvements → Analytics Data → `sysdiagnose_…`**; share to your computer.
- **The correlation that wins:** hand Apple the **exact CellGuard Silent-Failure timestamp** plus the sysdiagnose captured seconds later. Engineering lines the app-level timeout up against the baseband trace at that instant (PDU/PDP deactivation, RRC issue, network reject code, etc.).

### C. Remediation you can claim (Switzerland primary; EU/Germany secondary)

You have **met the threshold** for more than another swap: Swiss consumer-protection practice holds that a buyer need only tolerate **~2–3 failed repair/replacement attempts** — you're at **two replacements / three units** with the defect persisting.

**Crucial — who you direct the legal demand to depends on where you bought it:**
- **Bought directly from Apple** → Apple is seller + manufacturer; demand the remedy from Apple.
- **Bought from a retailer** (Swisscom, Sunrise, Digitec, …) → the **statutory 2-year warranty (OR Art. 197 ff.) runs against the SELLER**, not Apple. Apple handles hardware swaps, but the legal demand for **refund / price reduction** goes to the **retailer**.

**Your statutory options (Swiss OR Art. 197 ff. / 205 / 206):**
- **Wandelung** (rescission → full refund) — justified now after repeated failed attempts.
- **Minderung** (price reduction) — if you keep the device.
- **Ersatzlieferung** (replacement) — effectively exhausted (3 units).

**EU angle** (if bought in Germany/EU): Directive 2019/771 Art. 13 grants refund/price-reduction when a defect persists despite the seller's repair attempts — a systemic 3-device failure clearly qualifies.

**Apple goodwill remedies Customer/Executive Relations can authorize:**
- Full **refund / buyback** outside the return window.
- **Model substitution** (e.g. iPhone 16 Pro Max, or any non-affected model) + refund of the price difference.
- **AppleCare+ refund** and/or **store credit** if you keep the device (a de-facto *Minderung*).

**Ask in this order (tiered):**
1. **Full refund (Wandelung).**
2. **Swap to a different model** unaffected by the iOS 26 baseband issue, refunding any price difference.
3. **AppleCare+ refund + store credit** if forced to keep the device.

> Leverage: a **formal written demand** (email or registered letter) to the seller/Apple carries more weight than a phone call, and naming the **SKS** signals you know your rights. Wording template in §12.

---

## 10. Talking Points for the Senior-Support Call

1. **Lead with the elimination, not the symptom.** "This is not a defective unit. I have reproduced it across 3 devices, 3 SIMs, 2 carriers, and 2 countries, with and without VPN, and with a clean fresh-set-up phone. The only constant is the iPhone 17 Pro Max on iOS 26."
2. **Name the signature precisely.** "Silent data stall — `NWPathMonitor` reports `satisfied` on 5G NR-NSA, full bars, but no data transits; confirmed dead against two independent hosts. Recovers on Airplane Mode."
3. **Offer structured evidence.** "I have a timestamped log of two-host-confirmed failures and can capture a sysdiagnose timed to a failure for baseband-log correlation. I will file / have filed a Feedback Assistant report (FB#: ______)."
4. **State what you want** (see §9 once completed) — escalation to engineering, and the remediation you are entitled to after repeated failed replacements.
5. **Be cooperative but firm:** you are not asking for another like-for-like swap (that has failed 3×); you are asking for **engineering attention and an appropriate remedy.**

---

## 11. Status of Next Tests (live)

- [ ] iOS 26 **baseline** data-collection run (no VPN) — _in progress_
- [ ] **5G Auto / LTE** A/B (highest diagnostic value — isolates the NR-NSA path)
- [ ] (Optional, low value) VPN windows — Tailscale, then Proton — VPNs already exonerated
- [ ] iOS 27 test (sequenced after baseline; pending §8 research)
- [ ] Capture a **sysdiagnose** immediately after a confirmed Silent Failure
- [ ] File / update **Feedback Assistant** report; record FB#

---

## 12. Templates

### 12a. Remediation letter (to Apple Customer Relations, or to the retailer if you bought it there)

> Dear Customer Relations Team,
>
> I am writing regarding my **iPhone 17 Pro Max** (Serial: ________), purchased on ________ from ________. The device has a persistent, systemic cellular connectivity defect that prevents core use of the phone.
>
> To date I have received **two warranty replacement units** (Cases: ________, ________). The **identical defect is present on all three units**, and I have further reproduced it across two carriers, two countries, multiple SIMs (physical, eSIM, and a foreign travel eSIM), with and without any VPN, and on a unit set up fresh without a restored backup. This indicates a **systemic iOS 26 / baseband software flaw**, not a single defective unit. My home carrier has confirmed no comparable reports and no fault on my line.
>
> Under Swiss consumer law (**OR Art. 197 ff.**) and established consumer-protection practice, a buyer is not required to tolerate an indefinite repair/replacement loop. Having exceeded a reasonable number of attempts, I am exercising my right to **Wandelung** (rescission) and requesting a **full refund**. Alternatively, I would accept **substitution with a different model** not affected by this defect, with the price difference refunded.
>
> Given the time I have invested — including building a custom diagnostic tool that captures two-host-confirmed, timestamped evidence of the failure — I ask that you escalate this to a senior **Customer Relations / Executive Relations** specialist authorized to resolve it, and that the technical evidence (Feedback Assistant **FB#: ________**, plus a sysdiagnose timed to a failure) be forwarded to engineering.
>
> I look forward to your prompt response.
>
> [Name] · [Phone] · [Apple ID email]

*(If you bought from a retailer, address the refund demand to that retailer — the statutory warranty runs against the seller — while still pursuing Apple for the engineering fix.)*

### 12b. Feedback Assistant bug report

```
Title:
[Baseband/Cellular] iPhone 17 Pro Max: silent 5G NR-NSA data stall — NWPath .satisfied but zero connectivity ("attached but unreachable")

System Configuration:
- Device: iPhone 17 Pro Max
- iOS: 26.x (Build ____)
- Modem firmware: ____ (Settings > General > About)
- Carrier / carrier-settings bundle: ____ (____)
- SIM: ____ (reproduced on physical SIM, home eSIM, and a foreign travel eSIM)

Summary:
On 5G NR-NSA the device shows full bars and NWPathMonitor reports status = .satisfied on
cellular, yet no data transits — confirmed dead against two independent hosts
(captive.apple.com and Cloudflare) on fresh connections. The OS/CommCenter does not detect
the stall. Recovers only via Airplane-Mode toggle.

Reproduced across (rules out unit / SIM / carrier):
3 device units; physical SIM + home eSIM + foreign travel eSIM; 2 carriers; 2 countries;
with and without VPN; current unit set up fresh (no restored backup). The only constant is
iPhone 17 Pro Max + iOS 26.

Steps to Reproduce:
1. Wi-Fi off, cellular only, device on 5G NR-NSA.
2. Use normally / attempt to load a fresh host.
3. Observe full bars + path .satisfied, but new connections to multiple independent hosts
   time out (~10 s).

Expected: real data connectivity, or the OS reflects loss of the data plane.
Actual:   data plane silently dead while OS reports a healthy path; persists until
          Airplane-Mode toggle.

Logs / correlation:
- Diagnostic app (CellGuard) two-host-confirmed Silent Failure events with ISO-8601
  timestamps (CSV/JSON attached).
- Sysdiagnose captured within ~15 s of a failure with the Baseband logging profile active.
  Failure timestamp: ____ ; sysdiagnose triggered: ____ .
```

---

*Appendix: full event logs exportable from CellGuard (CSV/JSON). Supporting research files (iOS 26/27 cellular state, consumer remediation, escalation playbook, and the earlier technical analyses) available on request.*
