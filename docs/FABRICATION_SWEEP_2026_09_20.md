# Fabrication sweep — 2026-09-20 (read-only audit)

Audited at HEAD `720f0d0` with Commits 12 and 13 uncommitted in the working tree
(11 modified files; none touched by this audit). No source file was changed.

**Principle under audit:** a value shown to the user, stored as history, or fed to
the AI must be measured. A check that could not run is neither a pass nor a fail.

**Method.** Two passes over `NetoSensei/`: (1) pattern search for the six shapes
this project has been removing since Phase 2.1 — literal sentinels (999 / 100 % /
hard-coded scores), a failure's duration stored as a measurement, `?? 0` on an
optional measurement, derived values presented as measured, invented defaults,
and did-not-run counted as passed; (2) a reachability map from `MainTabView`
(Home / Diagnose / Speed / Security / History) so every hit is labelled with the
surface that renders it and whether a user can reach it today. Every LIVE item
below was re-read in the source by hand; DEAD items were confirmed by caller
count outside their own file.

Severity: **S1** = a wrong number/verdict on a tab root or a one-tap surface;
**S2** = wrong value on a reachable secondary screen, or stored into history the
user later reads; **S3** = reachable but only influences a branch/label with a
mild effect, or only visible to the AI; **DEAD** = unreachable today (kept in
the list because the file still compiles and can be wired back).

**Reachability baseline (from `MainTabView`, 5 tabs).** Only 6 of 28 files in
`Engines/` are reachable (`DiagnosticsEngine` + `DiagnosticLogicEngine`,
`PerformanceEngine`, `RoutingEngine`, `SecurityEngine` through the Advanced
Diagnostics sheet; `InterpretationEngine` through the Home VM and the Security
tab evidence card). Orphaned with zero callers: `SecurityIntelligenceEngine`
and its 13 scanners, `VPNAutoScorer`/`VPNModeBenchmark`/`VPNFailurePredictor`,
`VPNBenchmarkEngine`, `Engines/DNSBenchmark`, `AdvancedDiagnosticService`,
`NetworkSecurityAuditService`, `NetworkSecurityScanner`, `SecurityScanService.
runFullSecurityScan`, `StreamingDiagnosticService.diagnoseStreaming`,
`NetworkInterpreter`, `RootCauseAnalyzer` (never invoked; only its nested
`Analysis` type is named), `ProblemSolutions`, `VPNOptimizer` (its sheets hang
off an uncalled `handleAutoFix`), `DiagnosticDataCollector`, `VPNSnapshotManager`.
`NetworkDebugView` is `#if DEBUG` only.

---

## 1. LIVE fabrications, by severity

### S1 — tab roots and one-tap surfaces

| # | Where | What it fabricates | Surface |
|---|---|---|---|
| 1 | `Services/NetworkMonitorService.swift:717-726` `getDNS` | A failed or timed-out lookup returns `latency` = the **1.5–2 s timeout** with `lookupSuccess: false`. `DNSInfo.displayableLatency` guards it, but `DashboardViewModel.updateSmoothedValues` (`:798`) smooths the **raw** `dns.latency`, and the Home DNS card renders `smoothedDNSLatency` first (`DashboardView.swift:1010`). `hasDNSWarning` (`DashboardViewModel:598`) also reads the raw value, and `recommendedDNS` is set from the timeout. | **Home tab** DNS card + "DNS slow" warning |
| 2 | `ViewModels/DashboardViewModel.swift:637-675` `vpnHealthScore` | Starts at 100 and only subtracts when a metric is non-nil. Overhead nil + tunnel latency nil + loss nil ⇒ **100 / "excellent"** with nothing measured. | **Home tab** VPN card (VPN on) |
| 3 | `ViewModels/DashboardViewModel.swift:626-634` → `DashboardView.swift:978` | `vpnOverhead = external − gateway` is labelled **"VPN adds ~N ms latency"**. That difference is the whole internet leg, present with or without a VPN; it is attributed to the VPN by assertion. | **Home tab** VPN card |
| 4 | `Views/CombinedSecurityCheckView.swift:162-198` `computeVerdict` | All inputs optional; when every check is nil (never ran, timed out) `issueCount == 0` ⇒ **`.secure`**. Did-not-run counted as passed. | **Security tab** → "Run Full Security Check" |
| 5 | `Services/PrivacyShieldService.swift:369-386` `checkDNSPrivacy` | Reads `dns.resolverIP`, which is **never assigned non-nil anywhere** (`NetworkMonitorService:295, :721` only write `nil`). With a VPN on the check always reports `passed: true, "DNS queries go through your VPN"`. Also `:664-667` captive-portal catch ⇒ passed; `:682-693` unresolved CFHost ⇒ "DNS appears normal"; `:555-559` SSID present ⇒ passed with no property checked. | **Security tab** "Am I Protected?" 6-check card |
| 6 | `ViewModels/StreamingDiagnosticViewModel.swift:100, :105, :117, :251` | **Still present, still reachable** (Speed tab → streaming section, `SpeedTabView.swift:188/225/444`). `wifi = -50` ("assume decent WiFi"), `dns = … ?? 50.0`, `vpnImpact = vpnActive ? 20.0 : nil`, `compareVPNImpact()` returns a constant `20.0`. Effect on screen: 20 > 15 at `:301-303` so **"Vpn" is listed under Contributing Factors whenever a VPN is on**, and `vpnActive` itself is derived from the invented impact. −50 dBm and 50 ms are stored in the result (`wifiStrength`, `dnsLatency`) and silently make `.wifi`/`.dns` bottlenecks impossible; `wifiStrengthText` ("-50 dBm") exists but no view prints it today. | **Speed tab** streaming card |
| 7 | `Services/TracerouteService.swift:69, :93, :136-229` | Timed-out hop ⇒ `latency = medianLatency ?? 0`; gateway/DNS/1.1.1.1/VPN/final latencies `?? 0`; gateway host `?? "192.168.1.1"` (`:135`) is then "measured". A silent hop renders as **0 ms** and `latencyChange` goes negative. | **Diagnose tab** → Traceroute |
| 8 | `Engines/PerformanceEngine.swift:98-102, :173, :180` (via `DiagnosticsEngine` → `AdvancedDiagnosticViewModel`) | Jitter samples include **failed pings' durations** (return value discarded); on failure `packetLoss = 100.0`, `jitter = 999`. | **Diagnose tab** → Advanced Diagnostics |
| 9 | `Engines/DiagnosticsEngine.swift:68` | `measureLatency` returns **999.0** when no ping succeeded. | **Diagnose tab** → Advanced Diagnostics |

### S2 — stored into history or shown on a secondary screen

| # | Where | What it fabricates | Surface |
|---|---|---|---|
| 10 | `ViewModels/SpeedTestViewModel.swift:183-184`, `ViewModels/DiagnosticViewModel.swift:209-210`, `Services/NetworkHistoryManager.swift:156-157` | `gatewayLatency`/`dnsLatency` written as **`?? 0`** into `NetworkHistoryEntry` (both fields non-optional). `NetworkHistoryManager:161` stores `vpnOverhead = (tunnel ?? 0) − (router ?? 0)` (can be 0 or negative). `bestNetwork` averages (`:288-291`) include the zeros. | **History tab** charts / best-network summary |
| 11 | `ViewModels/DiagnosticViewModel.swift:216` | `healthScore = composed.score?.value ?? 0` — an **unscored verdict is stored as 0** because `NetworkHistoryEntry.healthScore` is `Int`. | **History tab** "Health Score Over Time" (`NetworkHistoryView:304`) |
| 12 | `Views/ConnectionComparisonView.swift:271, :280, :289, :298` + `Services/ConnectionComparator.swift:48, :669-682, :702-703` | Unmeasured side defaulted to **999 ms / 100 ms / 50 ms jitter / 0 Mbps** to declare a Wi-Fi-vs-cellular **winner**; `overallScore` uses `upload ?? 0`. | **Diagnose tab** → Wi-Fi vs Cellular |
| 13 | `Services/DiagnosticEngine.swift:149-160, :182-191` (via `AIPreflightCollector`) | Failed DNS lookup / HTTP GET stores the **elapsed timeout as `latency`** on a `.fail` test; `AIPreflightCollector:415` forwards it as `latencyMs`. | AI chat snapshot (Diagnose tab → AI) |
| 14 | `Services/NetworkMonitorService.swift:836-905` `performLocalPing` | `start` is taken once before trying ports 80/443/53 (1 s each); a success on the second port reports latency **including the failed first attempt**; the UDP fallback reports a "latency" after up to 3 s of failures with **no round trip at all**. | Home gateway card, Quick Check gateway row |
| 15 | `Services/ConnectionStabilityMonitor.swift:416-420` | Quality ladder on `avgLatency ?? 0` etc.: unmeasured ⇒ **"excellent"**. (Commit 7 fixed self-interference, not this default.) | Home stability events |
| 16 | `Services/ConnectionCapabilityAnalyzer.swift:184-186`, `Models/SpeedTestResult.swift:330-332`, `Views/SpeedTabView.swift:256` | ping/jitter/loss `?? 0` ⇒ capability rating is **best case when unmeasured** (documented as "no-penalty fallback", but the rating is shown as a judgement). | **Speed tab** "what can you do" checklist |
| 17 | `Views/NewAdvancedDiagnosticView.swift:994` | `wifi.channel ?? 0` renders **"Channel: 0"**. | Diagnose → Advanced |
| 18 | `Services/NetworkHistoryManager.swift:298-310` / `Models/NetworkStatus.swift:414-418` | Overall-score DNS component and history averages consume raw `dns.latency` (see #1), so a **timeout scores as a slow-but-real DNS**. | Home score (legacy path), History |

### S3 — branch-only, AI-only, or mild

| # | Where | What it fabricates | Surface |
|---|---|---|---|
| 19 | `Services/VPNBenchmark.swift:133-153` | A failure resolving in < 9.5 s stores `latencyMs = elapsed` on a `reachable: false` row. The Speed tab row gates on `reachable` so it is not printed; `AIPreflightCollector:606` reads the rows. | AI snapshot |
| 20 | `Engines/InterpretationEngine.swift:122, :184-185, :393-394` | `packetLoss ?? 0`, `jitter ?? 0` ⇒ no deduction ⇒ **score inflates** when unmeasured. | Diagnose → evidence card (5-score) |
| 21 | `Services/TrendAnalyzer.swift:148`, `Models/CongestionAnalysis.swift:33, :139`, `Services/WiFiQualityEstimator.swift:187`, `Models/NetworkStatus.swift:136, :294-295` | `?? 0` in comparisons: unmeasured ⇒ "not lossy" / "consistent" / "stable"; `rssi ?? -100` ⇒ always "bad signal" (rssi is always nil on iOS). | Trends line, congestion text |
| 22 | `Services/SmartRecommendationEngine.swift:216-224`, `Services/DiagnosticEngine.swift:459-466`, `ViewModels/DiagnosticViewModel.swift:661` | `?? 0` in summary strings / thresholds (mostly paired with validity flags). | Recommendation text |
| 23 | `Engines/DiagnosticLogicEngine.swift:328` | "latency increase" `?? 0`. | Diagnose text |
| 24 | `Views/PortScanView.swift:89, :332`, `Services/PortScanner.swift:255`, `Services/DiagnosticEngine.swift:284` | Gateway `?? "192.168.1.1"` — a guessed host is then scanned/traced. `DefaultRouteResolver` (Commit 1) exists but these sites do not use it. (`NetworkSecurityScanner.swift:175` has the same literal but is dead.) | Security → Port Scan, Traceroute, AI |

**Not fabrications, checked and cleared:** `DashboardView.swift:220` ring `trim(… ?? 0)` — documented "empty ring + —" for a nil score; `Helpers/Constants.swift` RSSI/DNS thresholds; `LegacySpeedRecordMigration` and `LatencyValidation.normalize` (they strip sentinels); `TLSAnalyzer.swift:528-530` (Commit 7: timeout is not a handshake); `DiagnosticViewModel.swift:417-425` (refuses failed-lookup elapsed); `Services/DNSBenchmarkService.swift` (the live DNS benchmark uses `nil` for skipped/failed servers).

---

## 2. DEAD fabrications (compile, unreachable today)

Confirmed by zero callers outside their own file / only reachable through
`SecurityIntelligenceEngine`, whose only entry view was deleted in `51c9687`.

| Where | What it fabricates |
|---|---|
| `Engines/GatewaySecurityScanner.swift:36-44, :62-72, :207, :220` | `securityScore: 80`, `handshakeSuccessRate: 100.0`, `gatewayLatency: 0` on the always-taken disabled branch; `999.0` on timeout; `pingGateway` (`:226-231`) always returns false. **Still hard-coded 80.** |
| `Engines/IPReputationScanner.swift:26-41, :138` | `isBlacklisted: false` etc., `reputationScore: 100` when the IP is unknown. **Still hard-coded false.** |
| `Engines/SecurityIntelligenceEngine.swift:62-74, :89-100, :1078` | DNS status invented with `securityScore: 75` ("skip complex scans that hang"); gateway timeout ⇒ 80; `finalScore >= 80 ⇒ .secure`. **Still 75.** |
| `Engines/LatencyStabilityScanner.swift:96, :141, :164`, `WiFiSaturationScanner.swift:104, :124`, `ISPThrottlingScanner.swift:98, :183, :196`, `NetworkBehaviorScanner.swift:329`, `VPNBenchmarkEngine.swift:163-170`, `VPNFailurePredictor.swift:185-285`, `VPNModeBenchmark.swift:230-260` | `999.0` / `(999, 999, 100)` on any failure; stub pings that always return 999. |
| `Engines/DNSBenchmark.swift:245-266, :319-321` | Skipped servers stored as 999/999/999 (the live `DNSBenchmarkService` does this correctly with nil). |
| `Engines/RouterConfigScanner.swift:88-91, :141`, `NATBehaviorScanner.swift:99, :126`, `TLSIntegrityScanner.swift:49-52`, every `var score = 100` scorer in `Engines/` | TTL 64 "default assumption", MTU `?? 1500`, NAT type guessed `.restrictedCone`, port-forwarding `return true`; scorers start at 100 and only subtract, so an offline scan scores 100. |
| `Services/AdvancedDiagnosticService.swift:78, :168-189, :305, :328-338, :490-492, :513-515, :544-549, :650-654, :616` | Failure durations as latency/jitter; `estimatedSpeed = 100 − latency×0.5`; channel 6 / 2.4 GHz / −60 dBm placeholders; **three simulated neighbour networks** at −65/−70/−75 dBm; a 0.5 s sleep as "router load". |
| `Services/StreamingDiagnosticService.swift:79, :97, :154, :202-218, :243, :263, :283-288, :319, :339, :365-369, :403` | rssi `?? -50`, throughput "estimated from latency" (100/50/25/10 Mbps), `"Unknown Region"`, timeout ⇒ 100 % loss / 0 jitter / "no congestion", VPN impact from a rough formula, peak-hours by wall clock. Only `.shared` is instantiated (`NetoSenseiApp:326`); the ViewModel never calls it. |
| `Services/NetworkSecurityAuditService.swift:297-303, :353-359, :432-440, :533-539, :580-586, :640-646, :220-223` | Six checks fall through to `.passed` when they could not evaluate (no AF_INET entry, no TLS challenge captured, proxy API nil, GeoIP failed, SSID not in a keyword list). `runFullAudit` has **no callers** (only two comments mention the class). |
| `Services/SecurityScanService.swift:435, :663, :850-868` + `Models/SecurityScanResult.swift:93-100` | `return false // Placeholder` detectors ⇒ `threats.isEmpty ⇒ .secure`, `safetyScore = 100`. `runFullSecurityScan` never called; `currentScan` is always nil (AIChatService reads it). |
| `Services/NetworkInterpretation.swift:190-194, :303-310`, `Views/Components/ProblemSolutions.swift:94, :200` | `vpnOverhead = max(0, ext − 30)` ("assume 30 ms baseline"); "VPN adds ~40 %" = `latency × 0.4`. Both files carry DEPRECATED headers and have zero callers. |
| `Services/VPNSnapshotManager.swift:169-196, :260-275, :414` | `?? 0` into stored snapshots; unmeasured ⇒ "Stable"/"predictable". |
| `Engines/VPNAutoScorer.swift:78` | `dropRate ?? 0`. |
| `Services/VPNOptimizer.swift:586` → `Components/FixActionSheets.swift:916` | `estimatedLatency = distance/100 + 10` rendered as "Est. Latency N ms". The only route to these sheets is `DiagnosticView.handleAutoFix`, which has zero callers, so `VPNOptimizer` is unreachable. |
| `Services/DiagnosticDataCollector.swift`, `Services/NetworkSecurityScanner.swift:175`, `Services/WiFiQualityEstimator.swift:187`, `Models/CongestionAnalysis.swift` | Orphaned (0 callers). Listed in S3 above only where a live twin exists. |

---

## 3. Explicit confirmations requested

- **Streaming view model invented defaults: PRESENT and REACHABLE.**
  `StreamingDiagnosticViewModel.swift:100` (`-50`), `:105` (`?? 50.0`), `:117`
  (`20.0`), `:251` (`return 20.0`), plus `:215` and `:221` in currently-uncalled
  helpers. Reached from the Speed tab via `SpeedTabView.swift:188/225/444`. The
  one that changes what the user reads is the 20 % VPN impact ("Vpn" contributing
  factor whenever a VPN is on). See S1 #6.
- **`GatewaySecurityScanner` 80 / `IPReputationScanner` false / `SecurityIntelligenceEngine` 75:** all still in the source, all still unreachable (Section 2).

---

## 4. Counts

| Bucket | Items |
|---|---|
| LIVE S1 | 9 |
| LIVE S2 | 9 |
| LIVE S3 | 6 |
| DEAD | 14 groups (≈ 95 individual sites) |

## 5. Recommended fix order (for the post-trip list)

1. `getDNS` timeout-as-latency (#1) — one function; make `latency` nil on failure. Every downstream `?? 0`/smoothing then needs the nil.
2. Home VPN card: `vpnHealthScore` nil when nothing measured (#2); rename "VPN adds ~N ms" to what it is, or compute overhead only as `tunnelLatency` (#3).
3. `CombinedSecurityCheckView.computeVerdict` → Coverage/`.unknown` when inputs are nil (#4); `PrivacyShieldService` checks → `.notRun`/N/A instead of passed (#5). Both belong to the Security-tab migration to `NetworkVerdict`.
4. Streaming VM: delete −50 / 50 / 20 and make the three inputs optional (#6).
5. Traceroute, PerformanceEngine, DiagnosticsEngine nil-on-failure (#7–#9).
6. History: make `NetworkHistoryEntry.healthScore/gatewayLatency/dnsLatency` optional with `decodeIfPresent` (#10, #11).
7. Everything in Section 2 is deletion candidates, not fixes.
