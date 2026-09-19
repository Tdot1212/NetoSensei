# NetoSensei Diagnosis v2 — Design (Accuracy Audit Phase 5)

**Date:** 2026-09-19
**HEAD at design time:** `90081e1` (Phase 4, Trends honesty). Working tree clean.
**Status:** DESIGN ONLY. No production code was changed. This document is the only artifact of this phase; implementation follows user approval.
**Requirement (user's words):** "When it diagnoses, it needs to actually say what is actually wrong in a way that people could actually understand. Right now different functions say different things, which is extremely confusing. It should tell us exactly what is going on, what's actually causing it, why it's caused, and how to actually fix it — in a way that people could go and fix it. Or maybe we can't fix it."

---

## 0. Summary

Phases 1–4 made the *inputs* honest (no sentinels, no fabricated speeds, interception-aware latency, segmented trends). The *verdict* layer is still five independent engines that each compute their own score, pick their own root cause, and print their own words. They disagree by construction, not by bug:

| Producer | Score rubric | Root-cause priority | Top-band word | Rendered on |
|---|---|---|---|---|
| DashboardViewModel `calculateRawHealthScore` | RCA-clone, penalties −2…−50, hard-failure gates | (none; separate string logic) | Excellent ≥70 | Home ring |
| RootCauseAnalyzer `calculateHealthScore` | same numbers as above, but raw test pass/fail gates (−40/−40/−20) | wifi → router → **DNS** → internet → VPN | Good ≥70 / Fair ≥40 (DiagnosticView) | Diagnose tab ring |
| NetworkInterpreter `interpret` | different penalties (−5…−25), VPN-adjusted thresholds | no-internet → wifi → **VPN** → gateway → DNS → ISP | Excellent ≥80 | "What's happening", Diagnose root cause |
| NetworkStatus `overallHealth` | weighted 35/25/15/10/5/10 by throughput/loss/jitter/latency/DNS/reachability | (none) | Excellent ≥85 | `vm.overallHealth` switch (DashboardView:1024), AI snapshot |
| InterpretationEngine 5-score | five 0–100 sub-scores, own edges | card priority router → internet → dns → wifi → vpn | Strong ≥80 | Security tab "Diagnosis Evidence" |

Plus three more score-like verdicts on the Deep Scan / Security side (threat level, safety score, privacy shield, combined security verdict), none of which know whether the checks they summarise actually ran.

The design below replaces all of them with **one `NetworkVerdict`**, computed by **one composer** from **coverage-tagged check records**, rendered by every surface, in **one vocabulary**, with every finding carrying **evidence, cause, and exactly one action category** (user-fixable / fixable-elsewhere / not-fixable). A pre-trip subset (§F) lands the parts the user will hit on unfamiliar networks in the next two weeks.

---

## Part 1 — Pre-flight inventory

All `file:line` references are to the working tree at `90081e1`.

### 1.1 Every surface that produces a score, verdict, root cause, or explanation

| # | Surface (what the user sees) | Renders at | Computed by | Inputs | Thresholds / edges | Vocabulary |
|---|---|---|---|---|---|---|
| S1 | **Home health ring** (number + word) | DashboardView:195–216 | DashboardViewModel `calculateRawHealthScore` (:923–985), 5-sample mean, 3-reading hysteresis `updateHealthRating` (:988–1012) | router/internet/DNS `displayableLatency`, VPN overhead, router packet loss, `MeasurementValidityTracker` hard failures | word: ≥70 Excellent / ≥40 Fair / else Poor; penalties: router −2/−5/−10/−15 @10/30/60/100 ms; internet direct −5…−50 @50…400, VPN −10…−45 @100…800; overhead −5/−10/−20 @150/300/450; DNS −1…−10; hard failures −40/−40/−20 | Excellent / Fair / Poor |
| S2 | **Home status line** under the ring (`vm.connectionQuality`) | DashboardView:217 | DashboardViewModel `updateUIStatus` :373–445, `formatDiagnosticRootCause` :480 | last Quick-Check root-cause *category string* if <N min old, else VPN overhead, external latency, gateway latency | overhead >150 "High VPN latency" / >50 "Moderate"; external >200 "High latency — VPN routing / possible ISP issue" / >100 "Elevated" | free text, own edges |
| S3 | **"What's happening"** card | DashboardView:240–262 | `generateSimpleSummary` :1025 → prefers `NetworkInterpreter.current.summaryItems` if <5 min old, else its own 70/40 bands | NetworkInterpreter score + VPN overhead + top actionable rec | interpreter: ≥70 "working well" / ≥40 "okay but could be better" / else "has problems"; VPN >200 ms "slowing things down" | ✅ ⚠️ 🔴 🐢 🔒 💡 |
| S4 | **Issues & Solutions** card | DashboardView:80–82 → ProblemSolutions.swift:254 | `SolutionEngine.solutions(for:)` :37–239 | `status` (DNS, external, gateway, VPN, hotspot) | DNS >150 warn / >300 critical; external >200 (>500 critical); router = hard failure && !VPN | problem / info-warning-critical |
| S5 | **Smart Recommendations** | DashboardView:970 | SmartRecommendationEngine `generateRecommendations(from:)` :208–254 | validated latencies (`?? 0` with validity flags), speed test, `diagnosticResult` jitter/loss | (own) | title + priority |
| S6 | **Trends** card | DashboardView:297–341 | TrendAnalyzer (Phase 4) | segmented speed + diagnostic history | ±20 % download, +30/−20 % latency | title/description, ±/neutral |
| S7 | **Diagnose → Quick Check** ring + label | DiagnosticView:215–235; DiagnoseTabView:214 | RootCauseAnalyzer `calculateHealthScore` :704–778 from `DiagnosticResult` tests | six `DiagnosticTest`s (S8) | number: same penalties as S1 but gates on `result == .pass`: router fail −40, external fail −40, DNS fail −20; label 70/40 Good/Fair/Poor; ring colour 70/40 (`colorForScore` :411); DiagnoseTabView colours with `NetworkColors.forHealthScore` (80/60/40/20) | Good / Fair / Poor (label) vs Excellent… (colour scale) |
| S8 | **Quick Check summary + overall status** | DiagnosticView:239–246 | DiagnosticViewModel `evaluate` (:587–700) | six tests: gateway (:342, pings **hardcoded `192.168.1.1`**, 2 s), external (:369, 1.1.1.1), DNS (:396, apple.com lookup, >100 ms = warning), HTTP (:432), VPN (:458, **always `.pass`**), ISP (:497, **pings 1.1.1.1 again**, >200 ms or fail = warning) | any fail → `.poor`; any warning → `.fair`; else `.excellent`; "All tests passed! Your network is healthy." | poor / fair / excellent |
| S9 | **Quick Check "Root Cause"** | DiagnosticView:360–400 | prefers `NetworkInterpreter.current.rootCause` (RULE 6, NetworkInterpretation:480–545); falls back to RootCauseAnalyzer `beginnerExplanation` :425 | interpreter: same six tests re-fed at DiagnosticViewModel:198–215 | interpreter priority: no-internet → no-WiFi → VPN overhead >250 → >100 → gateway >100 → DNS >300 → ISP >300 → "VPN Connected" / "Network Healthy"; RCA priority: !wifi → !router → router >100/>50 → !DNS → DNS >100 → !internet → VPN overhead >100 → … | "VPN Is Slow", "Weak WiFi Connection", "Slow DNS", "ISP Congestion" vs "Gateway Latency Elevated", "DNS Failure", "ISP Outage"… |
| S10 | **Quick Check contributing factors / severity / why-it-matters / what-to-do** (IntelligentDiagnosticCard) | IntelligentDiagnosticCard.swift:85–130 (no caller outside its own file found) | RootCauseAnalyzer `calculateSeverity` :366, `whyItMatters` :555, `whatToDoNext`, `autoFix` :640–700 | RCA measurements | word: ≥90 Excellent / 75 Good / 60 Fair / 40 Poor / Critical; colour 80/60/40 | none/minor/moderate/severe/critical |
| S11 | **Deep Scan summary card** ("Diagnostic Summary" + threat pill) | NewAdvancedDiagnosticView:221–257 | `AdvancedDiagnosticSummary.overallThreatLevel` DiagnosticModels:186–210; `summaryText` :265 | DNS-hijack results (region logic), VPN leak `leaked` | score 0 → **Secure**; ≥25 Medium; ≥50 High; ≥75 Critical | Secure / Low Risk / Medium Risk / High Risk / Critical |
| S12 | **Deep Scan "Overall Assessment & Solutions"** | NewAdvancedDiagnosticView:259–340 | per-finding: `performanceAssessment` :430, `securityFindingForDNS` :404, VPN leak, WiFi text, routing sentence | PerformanceMetrics, DNS results, VPN leak, routing | perf: loss >5 red / >1 orange, jitter >30 / >15 | free text |
| S13 | **Deep Scan intelligent diagnosis** | NewAdvancedDiagnosticView:648 | DiagnosticLogicEngine `diagnose` :18 (`userFriendlySummary` NetworkDiagnosisResult:25–42) | localLatency (cloudflare.com HTTP), foreignLatency, loss, jitter, download | symptoms: local >100, loss >3, jitter >50, speed <10, jump >100; VPN-off router if (lat >20 && loss >0) or lat >50 | "Your WiFi or router is the bottleneck", "ISP may be throttling", "VPN server is overloaded or far away" |
| S14 | **Deep Scan safety score** | (inside S13 result; `safetySummary` NetworkDiagnosisResult:44) | DiagnosticLogicEngine `calculateSafetyScore` :87–150 | dnsHijack (+30), vpnLeak (+30), jitter >100 (+20) / >50 (+10), loss >10 (+20) / >5 (+10), foreign >500 && local <50 (+15) | ≥50 Suspicious / ≥30 Risky / ≥15 Caution / else **Safe** with canned reasons "DNS resolving correctly, Connection is stable" | Safe / Caution / Risky / Suspicious |
| S15 | **Security tab "Am I Protected?"** | SecurityTabView:97–170, explanation :384–398 | `PrivacyShieldStatus.overallStatus` PrivacyShieldService:24–39 | 6 checks: VPN, DNS privacy, IP hidden, **WebRTC (always passed, "Not applicable")** :424–434, HTTPS integrity, IPv6 leak | 6/6 passed → Protected; warning && ≥4 → Partial; ≥3 passed → Partial; else Exposed | Protected / Partially protected / Exposed; "All privacy checks passed" |
| S16 | **Security tab "Diagnosis Evidence"** (5-score) | DetailCards.swift:338–430 | InterpretationEngine `computeScores` :110–205, `determinePrimaryIssue`, `generateSummary`; `NetworkScores.summary` NetworkStatus:633–647 | facts from status + VPN result + last speed test | local: −10/−20/−40 @10/20/50 ms gw; domestic under VPN = flat 90; international from speed-test ping 50/100/200; privacy base 50 ± components; stability loss/jitter | Strong ≥80 / Good ≥60 / Fair ≥40 / Weak ≥20 / Poor |
| S17 | **"Run Full Security Check"** verdict | CombinedSecurityCheckView:367–390 | `computeVerdict` :161–197 | wifi safety, VPN leak, IPv6, captive portal, certs | critical → Unsafe; issueCount 0 → **Secure**, 1 → Partial, ≥2 → Unsafe; **nil result = 0 issues** | Network Secure / Partial Protection / Network Unsafe; "WiFi safety and VPN leak checks all passed." |
| S18 | **Status-level component health** (router/internet/DNS/VPN dots, `vm.overallHealth`) | DashboardView:1024; AI snapshot | `RouterInfo.health` NetworkStatus:132–150, `InternetInfo.health` :181, `DNSInfo.health` :194, `VPNInfo.health` :292, `NetworkStatus.overallHealth` :335–441 | raw status | router: loss >5 or lat >50 poor, <10 && 0 loss excellent; DNS <30 excellent / <100 fair; VPN <50 ms excellent; overall weighted, ≥85 → excellent unless any component fair | Excellent / Fair / Poor / Unknown |
| S19 | **History → Insights** | NetworkHistoryView insightsCard | HistoryInsightsEngine :27–47 | health-score halves | ±5 pts | Improving / Degrading / Stable / Need more data |
| S20 | **AI context** | AIPreflightCollector:340, AIChatService:178 | reads S18 `overallHealth`, S11 threat level, S8 result | — | — | inherits every inconsistency above |

### 1.2 The five health rubrics side by side

| Input | S1 Dashboard | S7 RootCauseAnalyzer | S9 NetworkInterpreter | S18 status.overallHealth | S16 InterpretationEngine (local) |
|---|---|---|---|---|---|
| Gateway 51 ms | −5 | −5 | 0 (VPN) / −5 (direct, >20) | latencyScore 0 (>50) ×10 % | −40 (>50) |
| External 382 ms, VPN on | −18 | −18 | −10 (>400? no → 0…) actually 0 (<400 good) | n/a (not in rubric) | domestic flat 90 |
| VPN overhead 331 ms | −10 | −10 | −10 (>250) | n/a | n/a |
| DNS 212 ms | −7 | −7 | −10 (>150) | dnsScore 0 ×5 % | n/a |
| DNS lookup timed out | −20 only after **2 consecutive** failures (`MeasurementValidityTracker` :32) | **−20 immediately** + becomes primary problem "DNS Failure" | −15 | poor | — |
| Gateway ping failed | −40 after 2 consecutive | **−40 immediately** + "Router Unreachable" (and the target is hardcoded `192.168.1.1`) | −20 direct / **−5 under VPN** ("VPN expected to mask router") | reachability 0 ×10 % | 20 |
| Top word edge | 70 | 70 (label) / 80 (colour) | 80 | 85 | 80 "Strong" |

The same six numbers therefore yield three different scores and two different root causes on the same screen. S1 and S7 were explicitly "kept in lockstep" (comment at DashboardViewModel :919–921) but diverge on exactly the input that matters most: *what a failed probe costs*.

### 1.3 Why the device log contradicted itself

`Score=60, RootCause=VPN Is Slow` / `Health Score: 10/100` / `DNS Failure`, one run:

1. Quick Check runs six tests with 2–3 s timeouts (DiagnosticViewModel:88–140). Under a VPN, a 2 s DNS lookup or a gateway ping to the hardcoded `192.168.1.1` can time out even though browsing works.
2. `evaluate` marks the test `.fail` (S8). **RootCauseAnalyzer** then gates on `result == .pass`: DNS fail = −20 and, by its priority order (:220–318), DNS failure outranks everything after router → primary problem **"DNS Failure"**, health ≈10 after the other penalties. That is the `📊 Health Score` line (:234).
3. The **same six tests** are re-fed to **NetworkInterpreter** (:198–215). Its rubric charges −15 for DNS and only −5 for an unreachable router under VPN, and its root-cause order puts VPN overhead >250 ms *above* DNS → **"VPN Is Slow", score 60** (:724).
4. The Home ring, meanwhile, uses neither; it charges the DNS failure nothing until `MeasurementValidityTracker` sees two consecutive failures, and shows its own smoothed number.

Nothing here is a coding slip. Three engines were each written to be "the single source of truth" (comments at DashboardViewModel:1024, DiagnosticViewModel:196, DiagnosticView:360) and all three are still live.

### 1.4 Verdicts that rest on checks that never ran (coverage blindness)

| Site | What happens on failure / timeout | Resulting claim |
|---|---|---|
| DiagnosticsEngine:112–118 | DNS-hijack test → `withHardTimeout` fallback `.success([])` | no DNS results → `dnsBehaviorType = .allNormal` → threat score 0 → **"Secure"**, summary "✓ No security threats detected" |
| DiagnosticsEngine:125–140 | VPN-leak test → fallback `VPNLeakResult(realIP: nil, vpnIP: "Test timed out", leaked: false, leakType: .noLeak)` | `leaked == false` → contributes 0 → **"Secure"**; S12 then prints "VPN is protecting your IP (Test timed out...). No leaks detected." |
| DiagnosticLogicEngine:141–147 | safety score 0 with no reasons | canned reasons "DNS resolving correctly", "Connection is stable" are appended **without any check having run** |
| CombinedSecurityCheckView:161–197 | a failed probe returns nil | nil → no issue → **"Network Secure — WiFi safety and VPN leak checks all passed."** |
| PrivacyShieldService:424–434 | WebRTC check is not applicable on iOS | counted as **passed** in the 6/6 that yields "Protected — All privacy checks passed" |
| DiagnosticViewModel:458–495 | VPN tunnel "test" | returns `.pass` in both branches; it is a lookup, not a test, but counts toward "All tests passed" |
| DiagnosticViewModel:497–540 | "ISP Performance" | pings the same `1.1.1.1` the External test just pinged; the two can disagree by chance and are reported as two independent findings |
| SecurityIntelligenceEngine:60–74 | hardcoded DNS status `securityScore: 75` | dead code since 51c9687 (verified in the aborted Phase 5 pre-flight); listed for completeness, no user impact |

### 1.5 Fabricated or estimated values inside the verdict logic (new in this pre-flight)

These violate the accuracy principle and must not survive into v2:

| Site | Fabrication |
|---|---|
| NetworkInterpretation:174–180 | if gateway latency is unknown, VPN overhead is **estimated** as `external − 30` ("assume 30 ms baseline") and then drives "VPN Is Slow" and the score |
| ProblemSolutions.swift:93 | "High Latency (VPN)" text claims the VPN "adds ~`Int(internetLatency * 0.4)`ms" — a fixed 40 % share, not a measurement |
| DiagnosticViewModel:345 | gateway test target is the literal `192.168.1.1`, not `status.router.gatewayIP`; on any 10.x / 172.x / cellular / hotel network the router is declared unreachable |
| SmartRecommendationEngine:216–218 | `displayableLatency ?? 0` feeds `vpnOverhead = tunnelLatency − gatewayLatency` (guarded by validity flags for *some* recs, not the subtraction) |
| DiagnosticLogicEngine:141–147 | canned positive reasons appended when nothing negative was found (see 1.4) |
| DiagnosticModels:186 | `.secure` is the zero state, so "no data" and "checked, clean" are the same value |

### 1.6 The word "Excellent"

Distinct scales found (edges in the unit of each metric):

| # | Meaning | Edge | Site |
|---|---|---|---|
| 1 | Home health word | score ≥70 | DashboardViewModel:988 |
| 2 | Health colour scale | score ≥80 | NetworkColors:73, DiagnoseTabView:214, IntelligentDiagnosticCard:86 (colour) |
| 3 | IntelligentDiagnosticCard word | score ≥90 | :93 |
| 4 | NetworkInterpreter status | score ≥80 | NetworkInterpretation:470 |
| 5 | status.overallHealth | weighted ≥85 and no component fair | NetworkStatus:436 |
| 6 | Router status word / latency colour | <30 ms | DashboardView:1067, NetworkColors:21 |
| 7 | Gateway latency colour | <10 ms | NetworkColors:37 |
| 8 | RouterInfo.health | <10 ms && 0 loss | NetworkStatus:147 |
| 9 | DNSInfo.health | <30 ms | NetworkStatus:198 |
| 10 | DNS benchmark | <20 ms | DNSBenchmark:50 |
| 11 | VPN health (dashboard) | tunnel/overhead <30 ms | DashboardViewModel:798/806 |
| 12 | VPNInfo.health | <50 ms && loss <1 | NetworkStatus:294 |
| 13 | VPN health rating (detail card) | score ≥80 | DetailCards:222 |
| 14 | Signal strength | RSSI ≥ −50 dBm (not measurable on iOS) | DashboardViewModel:617, NewAdvancedDiagnosticView:1042 |
| 15 | Speed quality | ≥100 Mbps && ping <30 && loss <1 (direct); ≥20 Mbps (VPN) | SpeedTestResult:121/133 |
| 16 | Connection comparator | download ≥100 | ConnectionComparator:69 |
| 17 | Stability | >99 % uptime, <50 ms, 0 spikes | ConnectionStabilityMonitor:56 |
| 18 | Performance metrics | loss <1 && jitter <20 && throughput >25 | DiagnosticModels:141 |
| 19 | TLS | modern TLS version | TLSAnalyzer:63 |
| 20 | Streaming capability / video-call quality | various | SpeedTestResult:268/283 |

Twenty, not six. Plus a parallel set that avoids the word but is the same problem: "Strong" (S16), "Good/Fair/Poor" at 70/40 (S7 label), "Rock solid connection" (stability), "Protected", "Secure", "Safe".

### 1.7 Signals available for pattern recognition (what v2 can honestly detect)

| Signal | Source | Caveat |
|---|---|---|
| Connection type (WiFi / Cellular / Wired) | `NetworkStatus.connectionType` | reliable |
| Cellular radio technology (LTE / 5G / …) | `CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology` (ConnectionComparator:741–770) | works; carrier name returns "--" on iOS 16+ |
| Cellular signal strength / bars | **none** | no public API; any "strong signal" claim would be fabricated |
| Gateway RTT / loss / jitter | NetworkLatencyProbe (Phase 2.1 BSD handshake) | hidden under TUN VPN; N/A on cellular |
| External RTT + interception flag | `InternetInfo.latencyToExternal` / `latencyIntercepted` | nil when intercepted, never a stub number |
| Throughput, ping, jitter, loss | SpeedTestResult (Phase 3 honest) | on demand, not continuous |
| VPN state + authoritative flag | `SmartVPNDetector.VPNDetectionResult.vpnState / isAuthoritative` | inference path can false-positive on datacenter ISPs |
| Public IP country / ISP / ASN | `GeoIPService.currentGeoIP`, `VPNDetectionResult.publicCountry/publicISP` | with VPN on, this is the exit, not the SIM |
| Expected country | `SmartVPNDetector.getExpectedCountry()` :1156 — timezone map, then locale | timezone follows device location if auto-set |
| "Likely in China" | SmartVPNDetector:441–448 — IP country when VPN off, else `zh_CN` locale | locale heuristic when VPN on |
| Captive portal, DoH/DoT reachability, cert trust | CaptivePortalDetector, DNSEncryptionChecker, CertificateInspector | on demand |
| Consecutive probe failures | `MeasurementValidityTracker` (2 consecutive, 60 s window) | the only coverage-aware primitive today |

---

## Part 2 — Design

### A. One verdict model

Every surface renders from a single value object produced by a single composer. Nothing else computes a score, a root cause, or a health word.

```swift
struct NetworkVerdict: Codable, Sendable {
    let generatedAt: Date
    let context: VerdictContext          // what network / what mode this verdict describes
    let coverage: Coverage               // which checks ran, failed, were not applicable
    let state: OverallState              // the word; never derived from unrun checks
    let score: Score?                    // nil when coverage is below the floor — rendered "—"
    let primary: Finding?                // the one thing to deal with first (nil = nothing to fix)
    let findings: [Finding]              // all, ordered by severity; includes informational
    let headline: String                 // one plain sentence for the Home ring / status line
}

struct VerdictContext: Codable, Sendable {
    let segmentKey: String               // Phase 4 NetworkSegment key (+ country for cellular, §G)
    let connectionType: String
    let vpn: VPNContext                  // .off / .on(authoritative: Bool, exitCountry: String?) / .unknown
    let latencyIntercepted: Bool         // Phase 2.1
    let publicCountry: String?
    let expectedCountry: String?
    let likelyInChina: Bool
}

enum OverallState: String, Codable { case working, degraded, broken, unknown }

struct Score: Codable, Sendable {
    let value: Int                       // 0–100, ONE rubric, computed over ran checks only
    let band: Band                       // shared vocabulary (§D)
    let basedOn: [CheckID]               // which checks contributed
}
```

**Design choices (with alternatives — user decides):**

| Decision | Recommended | Alternative | Trade-off |
|---|---|---|---|
| A1 Keep a 0–100 number? | **Keep**, but `Score?` — nil below the coverage floor (§B), and one rubric for the whole app (RootCauseAnalyzer's calibrated penalties, taking optionals; the Dashboard clone is deleted) | Drop the number; state word + findings only | Users and Trends/History already consume the number; a nil-able score with a coverage line is honest and keeps continuity. Dropping it also breaks HistoryInsightsEngine and AI snapshots. |
| A2 One model for performance *and* security? | **One model**; each `Finding` carries `domain: .performance / .privacy`; Home renders the performance lens, Security tab renders the privacy lens; coverage rules are identical | Two structs (`NetworkVerdict`, `SecurityVerdict`) sharing `Finding`/`Coverage` | One model guarantees one vocabulary and one coverage line; two structs are easier to land incrementally. Recommendation: one model, but the Security tab migration is post-trip (§F). |
| A3 Where does the composer live? | New `Services/VerdictComposer.swift` (pure static functions over `[CheckRecord]`, unit-testable like Phases 2.1–4); engines become *check producers* that emit `CheckRecord`s and nothing else | Make NetworkInterpreter the composer | NetworkInterpreter contains an estimate fabrication (1.5) and its own vocabulary; cleaner to retire it than to grow it. |

### B. Coverage as a first-class concept

```swift
enum CheckID: String, Codable, CaseIterable {
    case gatewayReach, gatewayLatency, externalLatency, dnsResolve, dnsLatency, httpReach,
         vpnState, throughput, packetLoss, jitter,
         dnsHijack, vpnLeak, ipv6Leak, captivePortal, certTrust, dnsEncryption, wifiSafety
}

enum CheckStatus: Codable, Sendable {
    case ran(Measurement)                        // value + unit + when
    case failed(FailureReason)                   // .timeout, .blocked, .intercepted, .error(String)
    case notApplicable(String)                   // "No VPN active", "WebRTC only affects browsers"
    case notRun(String)                          // "Deep Scan only", "skipped: no Wi-Fi"
}

struct CheckRecord: Codable, Sendable { let id: CheckID; let status: CheckStatus; let source: String }

struct Coverage: Codable, Sendable {
    let records: [CheckRecord]
    var ran: [CheckID]; var failed: [CheckRecord]; var notApplicable: [CheckRecord]; var notRun: [CheckRecord]
    var line: String   // "5 of 7 checks completed · 2 couldn't run — DNS hijack test timed out; router ping: gateway address unknown"
}
```

Rules the composer enforces (each is a unit test):

1. **A failed check is never a pass.** `failed` contributes nothing to `score` and nothing to `state`, except: two consecutive failures of the same check within 60 s (reuse `MeasurementValidityTracker`) promote it to a Finding of kind `.checkFailingRepeatedly` with severity from the check's importance. One timeout is coverage, not a diagnosis.
2. **Coverage floor.** `score` is non-nil only if `externalLatency` (or `throughput`) ran **and** (`gatewayLatency` ran **or** is `.notApplicable` because of cellular / VPN hiding). Otherwise `score = nil`, `state = .unknown` unless a `broken`-severity finding exists (e.g. no internet at all), and the ring shows "—" with the coverage line beneath it.
3. **State from findings, not from arithmetic.** `working` = no finding above informational; `degraded` = at least one `poor`/`fair` finding; `broken` = any `broken` finding; `unknown` = floor unmet. The number and the word can therefore never disagree.
4. **Not-applicable is neither pass nor fail.** It is listed in the coverage line ("WebRTC: not applicable on iOS") and excluded from every count. This ends "6 of 6 passed" on the Privacy Shield.
5. **Synthesized fallbacks are banned.** DiagnosticsEngine's `.success([])` and the `"Test timed out"` `VPNLeakResult` become `.failed(.timeout)` records. `DiagnosticLogicEngine`'s canned "DNS resolving correctly / Connection is stable" reasons are removed; positive statements are generated only from `ran` records.
6. **Every surface prints `coverage.line`** next to the verdict, verbatim, in secondary text. Wording rule: numbers first, then the reasons in plain words, no check IDs.

### C. Finding output contract

```swift
struct Finding: Codable, Sendable, Identifiable {
    let id: UUID
    let kind: FindingKind                // named pattern (§E) or generic component finding
    let domain: Domain                   // .performance / .privacy
    let severity: Band                   // shared vocabulary (§D)
    let confidence: Confidence           // .high/.medium/.low + one-line reason (reuse CardConfidence shape)
    let headline: String                 // 1. WHAT'S WRONG — ≤ 60 chars, no jargon
    let evidence: [Evidence]             // 2. the measured numbers, with units and bands
    let cause: String                    // 3. WHY — one or two plain sentences
    let action: Action                   // 4. exactly one category
    let basedOn: [CheckID]               // checks that produced this finding
    let wouldSharpen: [CheckID]          // checks that did not run and would have raised confidence
}

struct Evidence: Codable, Sendable { let label: String; let value: Double; let unit: String; let band: Band; let comparedTo: String? } // "Your router: 4 ms (great) · Internet: 382 ms via VPN (fair for a VPN)"

enum Action: Codable, Sendable {
    case userFixable(steps: [String])                                   // ordered, doable now, on this phone or this router
    case fixableElsewhere(who: String, what: String, meanwhile: [String]) // "Your ISP", "Venue IT", "Whoever runs this router"
    case notFixable(why: String, expect: String, workarounds: [String])  // the missing category
    case none                                                            // informational only (state is working)
}
```

Writing rules (enforced by review, and by a unit test that scans headlines for banned tokens):

- Headline never contains: latency, jitter, DNS, gateway, packet, RTT, ms, throughput, ISP, CGNAT, MITM, TUN. Plain substitutes: latency → "delay"; jitter → "unsteady delay"; DNS → "address lookup"; gateway → "your router"; packet loss → "dropped data"; throughput → "speed"; ISP → "your internet provider" / "the carrier".
- Evidence always shows the actual number with unit **and** the band word from §D, and, where one exists, the comparison that justifies the band ("382 ms via VPN — fair for a VPN, would be poor without one").
- Cause is a mechanism, not a restatement ("Your VPN routes traffic through Los Angeles and back, which adds about 330 ms on top of your 4 ms home network").
- `notFixable` must always fill `expect` ("Video calls will lag; downloads and streaming will still work") and give at least one workaround or state "None right now".
- `fixableElsewhere` must name a party, not "someone".

Example, the roaming-SIM case:

> **Headline:** Your SIM is routing traffic through its home country
> **Evidence:** Internet delay 296 ms (poor) · your location: United States (timezone) · your traffic exits in China (IP lookup) · cellular, VPN off
> **Cause:** Roaming SIMs bought in China send all data back to China before it reaches the internet. That round trip adds roughly 150–300 ms to everything.
> **Action — Not fixable on this phone:** Nothing on your phone is wrong. **Expect:** web pages a beat slower, streaming fine, video calls and games laggy. **Workaround:** a local US eSIM gives you a direct route if low delay matters.
> Coverage: 4 of 5 checks completed · router check not applicable on cellular.

### D. One vocabulary

One five-band scale, one set of edges per metric, one table, one file (`Models/Bands.swift`). Every colour, word, and threshold in the app maps through it; the twenty scales in §1.6 are deleted.

```swift
enum Band: Int, Codable { case great = 4, good = 3, fair = 2, poor = 1, broken = 0 }
// words:  Great / Good / Fair / Poor / Broken     colours: green / blue / yellow / orange / red
```

| Metric (unit) | Great | Good | Fair | Poor | Broken | Source of edges |
|---|---|---|---|---|---|---|
| Score (0–100) | ≥80 | ≥60 | ≥40 | ≥20 | <20 | NetworkColors.forHealthScore — adopted |
| Router delay (ms) | <10 | <30 | <50 | <100 | ≥100 / unreachable | NetworkColors.forGatewayLatency — adopted |
| Internet delay, direct (ms) | <30 | <60 | <150 | <300 | ≥300 / unreachable | NetworkColors.forLatency — adopted |
| Internet delay, **via VPN** (ms) | <100 | <250 | <400 | <800 | ≥800 | new; edges from the RCA/Dashboard VPN rubric (justified: transpacific tunnels run 100–400 ms when healthy) |
| VPN overhead (ms) | <30 | <75 | <150 | <250 | ≥250 | NetworkColors.forVPNOverhead — adopted |
| Address lookup / DNS (ms) | <30 | <75 | <150 | <300 | ≥300 / fails | NetworkColors.forDNSLatency — adopted |
| Dropped data (%) | <0.5 | <1 | <3 | <10 | ≥10 | NetworkColors.forPacketLoss + one added edge |
| Unsteady delay / jitter (ms) | <5 | <15 | <30 | <50 | ≥50 | NetworkColors.forJitter — adopted |
| Speed, download (Mbps) | ≥50 | ≥25 | ≥10 | ≥5 | <5 | NetworkColors.forSpeed — adopted |
| Stability (uptime %) | >99 | >95 | >90 | >80 | ≤80 | ConnectionStabilityMonitor, one edge added |

Retired on adoption: the 70/40 Home word edges, 70/40 Diagnose label, 90/75/60/40 IntelligentDiagnosticCard words, 85/60/30 `overallHealth`, "Strong/Weak" (S16), "Rock solid", the RSSI scale (unmeasurable), `SpeedTestResult.QualityRating` (replaced by speed band + ping band), the 30/80/150 VPN-health words.

**Decision D1 — the word "Excellent":** Recommended: retire it and use "Great" for the top band, so that any remaining "Excellent" in the code is a grep-able leftover of an unmigrated scale. Alternative: keep "Excellent" as the single top-band word. Trade-off: users have seen "Excellent"; but the audit trail is cleaner if the old word disappears with the old scales.

**Decision D2 — bands under interception:** when `latencyIntercepted` is true, delay metrics have no band; they render "Via VPN/proxy" (Phase 2.1 language) and the finding §E3 explains it. No band is ever assigned to a value that was not measured.

### E. Named diagnostic patterns

Each pattern is a pure function `[CheckRecord] + VerdictContext → Finding?`, unit-tested with synthetic records. Detection uses only signals listed in §1.7; where a textbook signature needs a signal iOS does not expose, the pattern says so in `confidence` rather than assuming it.

| # | Pattern | Detection signature (all from measured records) | Plain explanation (cause) | Action category |
|---|---|---|---|---|
| E1 | **Crowded cell tower / venue** | cellular · VPN off or overhead ran · internet delay band ≤ poor **and** jitter band ≤ poor · (throughput ran and band ≤ poor) · no repeated probe failures. Signal strength is **not** available on iOS, so confidence is `medium("iOS cannot read signal strength; pattern inferred from delay + unsteadiness + speed")` | "Nothing on your phone is broken. Thousands of people are sharing this tower, so every packet waits in line." | **notFixable** — expect: messages fine, pages slow, calls/video choppy, uploads slow; workarounds: venue Wi-Fi if any, step outside the crowd / near a window, try again after the crowd thins, queue uploads for later, switch LTE↔5G in Settings (sometimes lands on a less loaded cell) |
| E2 | **Roaming SIM home-routed backhaul** | cellular · VPN off · `publicCountry` ≠ `expectedCountry` (timezone) and not in the same region group · internet delay ≥150 ms **and** jitter band ≥ fair (steady, just far). With VPN on the IP country is the exit, so the pattern is suppressed and `wouldSharpen` lists `vpnState`. Confidence `high` when GeoIP verified by 2 sources (`ipVerified`), else `medium` | "Your SIM sends traffic back to its home country before it reaches the internet, by design." | **notFixable** — expect: +150–300 ms on everything, streaming OK, calls/games laggy; workaround: local eSIM |
| E3 | **Local proxy / VPN answering probes** (Phase 2.1) | `latencyIntercepted == true` | "A VPN or proxy app on this phone answers the delay test itself, so the number would describe the app, not the network. Speed tests still measure real throughput through the tunnel." | **notFixable** (by design) — expect: no delay numbers while the proxy is on; workaround: turn the proxy off briefly to measure the raw network |
| E4 | **VPN tunnel overhead** (vs. the network) | VPN on · gateway delay ran and band ≥ good · internet delay via-VPN band ≤ fair · overhead = internet − gateway ≥ 150 ms (measured, never `ext − 30`) | "Your home network is fast (4 ms). The extra 330 ms is the round trip to your VPN's server." | **userFixable** — steps: pick a nearer server in the VPN app, try WireGuard, reconnect once |
| E5 | **Internet provider slow** (true ISP problem) | VPN off · gateway ran and band ≥ good · internet delay direct band ≤ fair (and/or throughput ≤ fair) · not E1/E2 | "Your router is fine; the slowdown starts after it leaves your home." | **fixableElsewhere** — who: your internet provider; meanwhile: retry later, cellular for urgent calls |
| E6 | **Can't tell VPN from network** (coverage-limited) | VPN on · gateway `.notApplicable("hidden by VPN")` or failed · internet delay ≤ fair | "The VPN hides the router, so I can't tell whether the delay is the VPN or the network." | **none** with `wouldSharpen: [gatewayLatency]`; step offered: "Disconnect the VPN for 10 s and re-run to separate them" (as an informational step, not a fix) |
| E7 | **Your router / Wi-Fi is the bottleneck** | Wi-Fi · gateway delay band ≤ poor **or** gateway dropped data band ≤ poor (two probes) | "Traffic is already slow before it leaves your home." | **userFixable** — move closer, restart router, fewer devices, 5 GHz |
| E8 | **Router unreachable** | gateway `.failed` twice in 60 s · Wi-Fi connected · target = real `gatewayIP` (never a literal) | "Your phone is on Wi-Fi but the router doesn't answer." | **userFixable** — toggle Wi-Fi, rejoin, restart router |
| E9 | **Captive portal** | `captivePortal` ran = portal detected | "This network wants you to log in on a web page before it lets traffic through." | **userFixable** — open the login page; then re-run |
| E10 | **Cross-border restriction (China, VPN off)** | `likelyInChina` · VPN off · domestic reachable · overseas HTTPS fails/timeouts | "Overseas sites are blocked at the border here, not by your network." | **notFixable** on this network — expect: domestic apps fine; workaround: VPN |
| E11 | **ISP DNS interception (regional)** | Deep Scan: overseas domains hijacked, domestic not | "Your provider answers overseas address lookups itself. Normal here, not an attack." | **notFixable** — expect: some overseas content unavailable; workaround: VPN / DoH if reachable |
| E12 | **Slow address lookup** | DNS latency band ≤ poor, lookup succeeds | "Every site waits for a slow address lookup first." | **userFixable** — set 1.1.1.1 / 8.8.8.8 in Wi-Fi settings |
| E13 | **IPv6 leaking around the VPN** | VPN on · IPv6 leak check ran = leak | "Some traffic uses a second address that skips the tunnel." | **userFixable** — disable IPv6 in the proxy app / use a profile that tunnels IPv6 |
| E14 | **Sharing a phone's hotspot** | connection is a tethered hotspot (existing SolutionEngine signal) | "You're on another phone's cellular connection." | **none** (informational), expect cellular behaviour |

Priority when several match: broken-severity first, then the most *specific* (E2 before E5, E4 before E5, E1 before generic "slow"), then informational. E1 and E2 never co-fire (E2 requires steady delay; E1 requires unsteady delay).

### F. Migration path

Principle: every step keeps the app shippable; each surface flips to the verdict when its producer emits `CheckRecord`s. No big-bang.

**Phase 5a — pre-trip (target ~2 weeks, ~10 working days):**

| Step | What | Files (est.) | Why pre-trip |
|---|---|---|---|
| 5a.1 | `Bands.swift` (vocabulary table), `Verdict.swift` (model), `VerdictComposer.swift` (pure composer: coverage rules B1–B5, one score rubric, state-from-findings) + unit tests | 3 new + tests; ~600 lines | Foundation; pure and testable like Phases 2.1–4 |
| 5a.2 | Quick Check emits `CheckRecord`s: fix gateway target to `status.router.gatewayIP` (`.notApplicable` on cellular / when unknown), drop the duplicate ISP ping and the no-op VPN "test", timeouts → `.failed(.timeout)` | DiagnosticViewModel | The hardcoded `192.168.1.1` fires "Router Unreachable / −40" on **every** hotel, venue and cellular network; this alone poisons the trip |
| 5a.3 | Dashboard status emits `CheckRecord`s from `NetworkStatus` (gateway, external, DNS, VPN, interception); delete `calculateRawHealthScore`, `updateUIStatus` string logic, `generateSimpleSummary` fallback | DashboardViewModel | Removes rubric #1 and text source #2 |
| 5a.4 | Home ring, status line, "What's happening", Diagnose ring/label/root cause render from the verdict; Diagnose result shows the primary finding in the §C layout; coverage line under both rings | DashboardView, DiagnosticView, DiagnoseTabView | The surfaces the user looks at on unfamiliar networks |
| 5a.5 | Patterns E3, E4, E5, E6, E7, E8, E12 (generic), plus E1 and E2 (cellular, trip-specific) with tests | VerdictComposer + `Patterns/` | E1/E2 are the trip; E4/E5/E6 end the "ISP Outage when the VPN was the cause" conflation |
| 5a.6 | Retire NetworkInterpreter and RootCauseAnalyzer as verdict producers (keep files, mark deprecated, no callers on the migrated surfaces); Issues & Solutions and Smart Recommendations cards render `Finding.action` instead of their own engines (SolutionEngine's `* 0.4` and Interpreter's `ext − 30` disappear with them) | 2 services, 2 cards | Ends rubrics #2 and #3 and both fabrications in §1.5 |
| 5a.7 | §G cellular-key country addendum | SpeedTestResult, DiagnosticHistoryEntry, NetworkSegment, SpeedTestEngine, tests (~40 lines) | Trip transition China → US SIM |
| 5a.8 | Live verification on simulator with a `CheckRecord` seeding probe (Phase 3/4 pattern); grep gates: no `192.168.1.1`, no `* 0.4`, no `ext - 30`, no `?? 0` feeding a verdict | — | Same bar as previous phases |

**Phase 5b — post-trip:**

| Step | What |
|---|---|
| 5b.1 | Deep Scan: DiagnosticsEngine fallbacks → `.failed(.timeout)`; threat level and safety score replaced by privacy-domain findings; DiagnosticLogicEngine and RoutingInterpretation become check producers; E10/E11 land here |
| 5b.2 | Security tab: PrivacyShield six checks → `CheckRecord`s (WebRTC `.notApplicable`); Combined Security Check verdict from the composer (nil probe = `.failed`, never "no issue"); E9, E13 |
| 5b.3 | Retire InterpretationEngine 5-score card (its evidence-card idea survives as `Finding.evidence`); `NetworkStatus.overallHealth` and component `.health` replaced by bands; AI snapshot and History read the verdict |
| 5b.4 | Delete deprecated engines; MEASUREMENT_AUDIT rows closed |

**Why this pre-trip subset:** the user's trip is Wi-Fi in China → US home Wi-Fi → China-bought roaming SIM in the US → congested venue. Every one of those is a Home-ring + Quick-Check moment, and two of them (E1, E2) are exactly the "nothing is wrong with your phone" cases that today read as "ISP Congestion" or "Router Unreachable". The Security tab is not what the user opens when a page is slow at a convention, and its migration touches four services. The one security item that *is* trip-relevant — captive portals at venues/hotels — already renders correctly in the Combined check; it moves to the model in 5b.

**Risk in 5a:** 5a.6 removes two engines from the Home and Diagnose surfaces at once. Mitigation: land 5a.1–5a.5 first (verdict rendered alongside, behind a DEBUG toggle for one build), compare on the developer's real networks, then flip.

### G. Scoped addendum — country in the cellular segment key

Phase 4 keys cellular as `Cellular|vpn|-|-`, so China cellular and a US roaming SIM share a segment. Change:

- `SpeedTestResult` and `DiagnosticHistoryEntry` gain `publicCountry: String?`, captured at test time from `GeoIPService.shared.currentGeoIP?.countryCode` (fallback `SmartVPNDetector.detectionResult?.publicCountry`). Observed only; nil when neither is available.
- `NetworkSegment.key` for cellular becomes `Cellular|<vpn|direct>|<country or ->`. Wi-Fi/wired keys unchanged.
- Old records have nil country → `Cellular|direct|-`, a coarse segment that never merges with keyed records (Phase 4 rule).

Honest limits, stated in the code comment and here:

1. With VPN **on**, `publicCountry` is the VPN exit, not the SIM. Two SIMs behind the same exit still share a key. Acceptable: what the user experiences (and what a trend should track) is the tunnel path.
2. A China-bought SIM roaming in the US is often **home-routed**, so its public IP is Chinese even in the US. The key then reads the same as China cellular — and that is correct: it *is* the same backhaul path, which is the whole point of E2. A US-local eSIM gets `US` and a separate segment.
3. Carrier name via CoreTelephony returns "--" on iOS 16+ (ConnectionComparator:743) and is not used.

Estimated diff: ~40 lines + 2 tests (key shape; old records don't merge).

### H. Open decisions for approval

1. **A1** number kept (nil-able) vs. no number — recommend keep.
2. **A2** one model with domain tag vs. two structs — recommend one.
3. **D1** retire "Excellent" for "Great" vs. keep the word — recommend retire.
4. **B2 floor** — is "external ran + (gateway ran or N/A)" the right minimum for showing a number? Alternative: require throughput too (then the ring is "—" until a speed test has run on this segment).
5. **Not-fixable findings and the score** — recommend they set `state = degraded` and appear first in findings, but carry a `byDesign` flag so the ring colour is yellow, never red, on a roaming SIM (the network is doing what it is designed to do).
6. **5a scope** — include E1/E2 (recommended) or ship only the generic patterns pre-trip and add cellular ones after real-world samples.
7. **Neutral coverage line on the Home ring** — under the word (recommended) vs. only in the expanded card.

---

## Part 3 — Also-fix list (report only; nothing changed)

| Item | Confirmed at | Belongs to |
|---|---|---|
| Streaming diagnostic returns a live `999.0` ping sentinel when no CDN answers | StreamingDiagnosticViewModel.swift:179 | **Separate, small** (Phase 3 pattern: return `Double?`, nil = unmeasurable; one consumer). Not v2. |
| History-entry gateway/DNS latency still written as `?? 0` | NetworkHistoryManager.swift:156–157 (`init(from status:)`), SpeedTestViewModel.swift:167–168, DiagnosticViewModel.swift:239–240 | **Separate, small** (Phase 4 pattern already applied to `latency`; make both optional, decoder strips legacy 0, CSV/baseline/chart nil-safe). |
| Recommendation engine reads display latency with a zero fallback | SmartRecommendationEngine.swift:216–218 (and :217 `vpnOverhead = tunnelLatency − gatewayLatency` where gateway may be the 0) | **v2 (5a.6)** — the engine is replaced by `Finding.action`; interim risk is bounded by the validity flags for most recs. |
| Trends card shows at most 2 insights with no ordering; neutral "Network changed" can displace a real finding | DashboardView.swift:324 `insights.prefix(2)`; TrendAnalyzer appends the neutral line first | **Separate, tiny** — sort by severity (negative → positive → neutral) before `prefix(2)`, or render the neutral line as a caption outside the 2-slot list. Can ride along with 5a.4 since that view is touched anyway. |
| *New:* Quick Check gateway test pings literal `192.168.1.1` | DiagnosticViewModel.swift:345 | **v2 pre-trip (5a.2)** — critical on the trip. |
| *New:* VPN overhead estimated as `external − 30` when gateway unknown | NetworkInterpretation.swift:174–180 | **v2 (5a.6)** — disappears with the engine; until then it is a fabrication feeding "VPN Is Slow". |
| *New:* "VPN adds ~40 % of your latency" | ProblemSolutions.swift:93 | **v2 (5a.6)** — same. |
| *New:* "ISP Performance" test is a second ping to the External target; "VPN Tunnel" test always passes | DiagnosticViewModel.swift:497–540, :458–495 | **v2 pre-trip (5a.2)**. |
| *New:* Deep Scan timeouts synthesize clean results; safety score appends canned positive reasons | DiagnosticsEngine.swift:112–140; DiagnosticLogicEngine.swift:141–147 | **v2 post-trip (5b.1)** — but if Deep Scan is used on the trip, the summary should at minimum say "couldn't run" (a one-line wording change could be pulled into 5a). |
| *New:* Privacy Shield counts WebRTC "not applicable" as passed | PrivacyShieldService.swift:24–39, :424–434 | **v2 post-trip (5b.2)**. |
| Dead code carrying a hardcoded DNS score 75 | SecurityIntelligenceEngine.swift:60–74 (orphaned since 51c9687) | Not user-visible; delete with 5b.4. |
