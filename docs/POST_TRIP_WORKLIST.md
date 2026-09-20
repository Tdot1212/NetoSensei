# Post-trip work list — collected 2026-09-20 (read-only audit)

Compiled at HEAD `720f0d0` with Commits 12 and 13 uncommitted. Every item below
was re-checked in the source on this date; where the earlier session notes were
wrong or stale, the entry says so. Companion: `FABRICATION_SWEEP_2026_09_20.md`
(the full list of fabricated values; items here reference its numbering as S1-#n).

**Type:** ACCURACY = a user can be shown something untrue today.
COMPLETENESS = a feature or coverage is missing; nothing untrue is shown.
SHIPPING = a policy/terms question, not a bug.

**Size:** S = one file, under a day. M = 2–5 files with tests. L = a design
decision plus a multi-file migration.

Ordered by user-visible harm, then by how much other work each unblocks.

---

## Tier 1 — untrue values on tab roots

### 1. DNS timeout stored as DNS latency → Home DNS card and "DNS slow" warning
- **Type:** ACCURACY. **Size:** M.
- **Where:** `Services/NetworkMonitorService.swift:717-726` (`getDNS` returns the
  1.5–2 s timeout as `latency` with `lookupSuccess: false`);
  `ViewModels/DashboardViewModel.swift:798` smooths the raw value,
  `Views/DashboardView.swift:1010` prefers the smoothed value, `:598`
  `hasDNSWarning` reads raw.
- **Why deferred:** `displayableLatency` was believed to guard every reader.
  It guards the fallback path only.
- **Blocks:** every downstream `dns.latency` consumer (items 2, 7, 8 here; AI snapshot).
- **Fix shape:** `latency` nil on failure; readers use the optional. Same
  contract Commit 6 gave the external target.

### 2. Home VPN card: health score 100 when nothing measured; "VPN adds ~N ms" is not VPN overhead
- **Type:** ACCURACY. **Size:** S.
- **Where:** `ViewModels/DashboardViewModel.swift:626-634, :637-675`;
  `Views/DashboardView.swift:939, :978`.
- **Why deferred:** surfaced during the Commit 8/10 captures (VPN was on in
  run 0); never scoped. Not in the earlier lists — new.
- **Blocks:** nothing. Standalone.
- **Fix shape:** `vpnHealthScore` → nil unless at least one input measured;
  overhead only from `tunnelLatency` (a measured tunnel round trip), or drop the
  "adds" wording.

### 3. Security tab, Full Security Check and "Am I Protected?" still on pre-v2 verdicts
- **Type:** ACCURACY (did-not-run counted as passed). **Size:** L.
- **Where:** `Views/CombinedSecurityCheckView.swift:162-198` (`computeVerdict`
  returns `.secure` when every input is nil); `Services/PrivacyShieldService.swift:369-386`
  (`checkDNSPrivacy` reads `dns.resolverIP`, which is never assigned, so it
  always passes with a VPN on), `:555-559`, `:664-667`, `:682-693`;
  `Views/SecurityTabView.swift` + `Components/DetailCards.swift` (DiagnosisEvidenceCard on
  `InterpretationEngine`'s 5-score, S3-#20).
- **Why deferred:** design doc §F scoped 5b to Home + Quick Check; the
  Security tab was explicitly post-trip in every brief since.
- **Blocks:** removing `InterpretationEngine`, `SecurityRating`-style enums,
  and the last non-`NetworkVerdict` verdict code.
- **Fix shape:** the migration the design doc describes: `Coverage` +
  `CheckStatus.notRun`/`.notApplicable` per check; verdict nil below a floor.
  Confirmed still true: `NetworkVerdict` appears in `Views/` only in
  `FindingsCard.swift`.

### 4. Advanced Diagnostics ("Deep Scan") still on `AdvancedDiagnosticSummary`
- **Type:** ACCURACY. **Size:** M.
- **Where:** `Views/NewAdvancedDiagnosticView.swift:181-224`
  (`overallThreatLevel`); `Engines/PerformanceEngine.swift:98-102, :173, :180`
  (failed-ping durations as jitter samples; `packetLoss = 100`, `jitter = 999`
  on failure); `Engines/DiagnosticsEngine.swift:68` (`999.0`).
- **Why deferred:** Commit 7 added `coverage`/`ThreatLevel.unknown` to the
  summary but did not touch the engines feeding it.
- **Blocks:** item 3 shares the verdict model.
- **Fix shape:** optional metrics out of `PerformanceEngine`; the summary's
  coverage already exists.

### 5. Streaming view model invented defaults (−50 dBm, 50 ms DNS, 20 % VPN impact)
- **Type:** ACCURACY. **Size:** S.
- **Where:** `ViewModels/StreamingDiagnosticViewModel.swift:100, :105, :117,
  :251` (+ `:215, :221` in uncalled helpers). **Confirmed present and reachable**
  via `Views/SpeedTabView.swift:188/225/444`. Visible effect: "Vpn" under
  Contributing Factors whenever a VPN is on (20 > 15 at `:301-303`).
- **Why deferred:** listed as out of scope in every brief from Phase 5b onward.
- **Blocks:** nothing.
- **Fix shape:** make the three inputs optional; drop the `.vpn` factor unless
  an impact was measured (there is no with/without-VPN measurement — say so).

---

## Tier 2 — untrue values stored or on secondary screens

### 6. History entries write gateway/DNS latency as `?? 0`
- **Type:** ACCURACY. **Size:** M.
- **Where:** `ViewModels/SpeedTestViewModel.swift:183-184`,
  `ViewModels/DiagnosticViewModel.swift:209-210`,
  `Services/NetworkHistoryManager.swift:156-157, :161` (`vpnOverhead` from two
  `?? 0`), `:288-291` (best-network averages include the zeros). Rendered by
  `Views/NetworkHistoryView.swift` charts. **Confirmed.**
- **Why deferred:** `NetworkHistoryEntry.gatewayLatency/dnsLatency` are
  non-optional (`NetworkHistoryManager.swift:28-29`); changing them needs the
  `decodeIfPresent` migration pattern from Phase 4.
- **Blocks:** honest history charts; item 1 makes the nils appear.
- **Fix shape:** optional fields + custom `init(from:)`; chart skips nil.

### 7. `NetworkHistoryEntry.healthScore` non-optional — unscored verdict stored as 0
- **Type:** ACCURACY. **Size:** S–M (same migration as item 6).
- **Where:** `ViewModels/DiagnosticViewModel.swift:216` (`?? 0`, with a comment
  admitting it); `Services/NetworkHistoryManager.swift:24`; chart at
  `Views/NetworkHistoryView.swift:304`. **Confirmed.**
- **Why deferred:** Phase 5b made the verdict score nil-able but left the
  history struct.
- **Blocks:** "Health Score Over Time" showing a real dip vs. a coverage gap.

### 8. Wi-Fi vs Cellular comparison declares a winner from defaults
- **Type:** ACCURACY. **Size:** S.
- **Where:** `Views/ConnectionComparisonView.swift:271, :280, :289, :298`
  (`?? 999`, `?? 0`); `Services/ConnectionComparator.swift:48, :669-682, :702-703`
  (`?? 100`, `?? 50`). Reachable: Diagnose tab → sheet.
- **Why deferred:** never audited; found in this sweep.
- **Fix shape:** a side with a nil metric cannot win that metric; "not measured" row.

### 9. Traceroute renders timed-out hops as 0 ms
- **Type:** ACCURACY. **Size:** S.
- **Where:** `Services/TracerouteService.swift:69, :93, :136-229`; gateway
  `?? "192.168.1.1"` at `:135`.
- **Why deferred:** never audited.
- **Fix shape:** `TracerouteHop.latency` optional; gateway from
  `DefaultRouteResolver` (exists since Commit 1).

### 10. Literal `192.168.1.1` gateway fallbacks
- **Type:** ACCURACY (a guessed host is scanned/traced and reported). **Size:** S.
- **Where (live):** `Views/PortScanView.swift:89, :332`,
  `Services/PortScanner.swift:255`, `Services/TracerouteService.swift:135`,
  `Services/DiagnosticEngine.swift:284`. (Dead twins: `AdvancedDiagnosticService`,
  `NetworkSecurityScanner`.) **Confirmed.**
- **Why deferred:** Commit 1 fixed Quick Check only.
- **Fix shape:** `NetworkMonitorService.detectedGateway()`; nil → the tool
  says "no gateway found" instead of scanning a guess.

### 11. AI snapshot receives failure durations as latencies
- **Type:** ACCURACY (AI-only). **Size:** S.
- **Where:** `Services/DiagnosticEngine.swift:149-160, :182-191` →
  `Services/AIPreflightCollector.swift:415`; `Services/VPNBenchmark.swift:133-153`
  (`latencyMs` on `reachable: false`, read at `AIPreflightCollector:606`).
- **Why deferred:** not user-rendered; the Speed tab row gates on `reachable`.

### 12. Gateway ping timing includes prior failed port attempts
- **Type:** ACCURACY. **Size:** S.
- **Where:** `Services/NetworkMonitorService.swift:836-905` (`start` before the
  80/443/53 loop; UDP fallback reports a "latency" with no round trip).
- **Why deferred:** new in this sweep.

### 13. Stability quality ladder and capability ratings treat unmeasured as best case
- **Type:** ACCURACY (mild). **Size:** S each.
- **Where:** `Services/ConnectionStabilityMonitor.swift:416-420`;
  `Services/ConnectionCapabilityAnalyzer.swift:184-186`,
  `Models/SpeedTestResult.swift:330-332`, `Views/SpeedTabView.swift:256`;
  `Engines/InterpretationEngine.swift:122, :184-185, :393-394`.
- **Why deferred:** documented as "no-penalty fallback" in Phase 3; the rating
  is nonetheless shown as a judgement.

---

## Tier 3 — completeness, churn, and hygiene

### 14. Cellular card reads only the NEWEST speed record
- **Type:** COMPLETENESS. **Size:** S.
- **Where:** `Views/DashboardView.swift:509`
  (`HistoryManager.shared.speedTestHistory.first`); matching rule in
  `Models/ConnectionCards.swift:80-90` (segment + 10 min). **Confirmed.**
- **Why deferred:** Commit 9 shipped the card; Commit 11 fixed the key source;
  the record choice was noted, not changed.
- **Fix shape:** pass the newest record whose `segmentKey` matches, not `.first`.

### 15. No verified mainland-China speed-test candidate
- **Type:** COMPLETENESS. **Size:** L (external verification, not code).
- **Where:** `Services/SpeedTestServerSelection.swift:193-199` (uncommitted
  Commit 12; the CN branch is `[cloudflare]` on purpose).
- **Why deferred:** every domestic LibreSpeed instance found is proof-of-work
  gated (USTC answers 500 without a token) or unreachable/intranet; Ookla is
  licensed personal-non-commercial; the Tokyo public backend answered 403.
- **Blocks:** any speed measurement on CMCC Wi-Fi without a VPN (device
  captures: Cloudflare probes 656 / 1518 / 724 ms → "Test Not Run").
- **Fix shape:** either a self-hosted `/__down`+`/__up` endpoint in a China
  region, or a negotiated backend. Must pass the 400 ms probe rule as-is.

### 16. LibreSpeed backends are volunteer/sponsor servers with no published usage policy
- **Type:** SHIPPING (App Store / terms question, not a bug). **Size:** n/a.
- **Where:** `Services/SpeedTestServerSelection.swift` (Clouvider LA / NYC /
  London / Frankfurt from librespeed.org's public list).
- **Notes:** the official `librespeed-cli` uses the same list by default; no
  policy text either way was found; sponsor names are shown in the label.
  Decide before release: keep, ask the sponsors, or self-host.

### 17. SSID briefly nil → identity key flips → smoothing buffers cleared twice
- **Type:** ACCURACY (transient: a cleared buffer shows a single raw sample as
  the smoothed value). **Size:** S.
- **Where:** `ViewModels/DashboardViewModel.swift:755-782`
  (`networkIdentityKey` includes `wifi.ssid ?? "-"`). **Confirmed in the
  2026-09-20 device log:** four `WiFi|CMCC-625E-5G|192.168.10 → WiFi|-|192.168.10`
  flips in one session.
- **Why deferred:** cosmetic churn; noted in Commits 8–10.
- **Fix shape:** key on subnet + type only, or treat nil↔value SSID as the same
  network when the subnet is unchanged (same idea as `PathIdentity`).

### 18. `IntelligentDiagnosticCard` orphan references deprecated `RootCauseAnalyzer.Analysis`
- **Type:** COMPLETENESS (dead code hygiene). **Size:** S.
- **Where:** `Views/Components/IntelligentDiagnosticCard.swift:11, :333`;
  also `Views/DiagnosticView.swift:573` (`handleAutoFix`, zero callers) and
  the eight fix sheets it alone presents. `RootCauseAnalyzer.shared` is never
  invoked anywhere. **Confirmed.**
- **Fix shape:** delete the card, `handleAutoFix`, and `RootCauseAnalyzer`.

### 19. Dead security engines still carry hard-coded scores
- **Type:** COMPLETENESS (unreachable; would become ACCURACY if wired back). **Size:** S (delete).
- **Where:** `Engines/GatewaySecurityScanner.swift:43, :71` (`securityScore: 80`),
  `Engines/IPReputationScanner.swift:28, :138` (`isBlacklisted: false`),
  `Engines/SecurityIntelligenceEngine.swift:74` (`securityScore: 75`). **All
  confirmed present and all confirmed unreachable** (zero callers outside
  `Engines/`; the only entry view was deleted in `51c9687`). 22 of 28 files in
  `Engines/` are dead; also dead: `AdvancedDiagnosticService`,
  `NetworkSecurityAuditService`, `NetworkSecurityScanner`,
  `SecurityScanService.runFullSecurityScan`, `StreamingDiagnosticService.diagnoseStreaming`,
  `NetworkInterpreter`, `ProblemSolutions`, `VPNOptimizer`, `VPNSnapshotManager`,
  `DiagnosticDataCollector`.
- **Fix shape:** delete, not fix. The audit doc `MEASUREMENT_AUDIT_2026_05_11.md`
  cites a UI location for these that does not exist.

### 20. Stale log wording "missing wifi-info entitlement"
- **Type:** COMPLETENESS (log only). **Size:** S.
- **Where:** the `[WiFi] CNCopyCurrentNetworkInfo unavailable (missing
  wifi-info entitlement)` line prints although the entitlement is present.
- **Why deferred:** cosmetic.

### 21. First-refresh startup-ordering artifact
- **Type:** COMPLETENESS. **Size:** S.
- **What:** the first dashboard refresh runs before GeoIP/VPN detection has a
  result, so the first verdict is composed at lower coverage and replaced ~30 s
  later. Commit 13 (uncommitted) narrows this: identity change → caches dropped
  → re-read; the first paint is still the pre-read one.

### 22. Commit 10 identity gate did not see VPN toggles (fixed in uncommitted Commit 13 — verify on device)
- **Type:** ACCURACY (stale rebuild). **Size:** done, unverified.
- **Where:** `Services/NetworkMonitorService.swift` `pathIdentity(for:)` —
  `viaTunnel` now = primary interface is `.other`. The device capture that
  proves a VPN toggle logs "VPN tunnel now carrying traffic" has not happened.

### 23. Commit 12/13 device captures outstanding
- **Type:** COMPLETENESS (verification debt). **Size:** one session at the phone.
- **What:** (a) Wi-Fi test, (b) 5G immediately after switching, (c) VPN toggle
  then test. Wi-Fi capture exists for Commit 12 (three "Test Not Run" runs);
  5G and VPN-toggle captures do not. Both commits stay uncommitted until then.

### 24. Upload has no trend insight; `HistoryManager.getAverageUploadSpeed` now skips unmeasured (Commit 12)
- **Type:** COMPLETENESS. **Size:** S.
- **What:** `TrendAnalyzer` has no upload-delta insight; when one is added it
  must read `measuredUploadSpeed`, never `uploadSpeed`.

### 25. `Views/NewAdvancedDiagnosticView.swift:994` renders "Channel: 0"
- **Type:** ACCURACY (minor). **Size:** S. `wifi.channel ?? 0` → hide the row.

---

## Counts

| Type | Count | Items |
|---|---|---|
| ACCURACY | 16 | 1–13, 17, 22 (fixed, unverified), 25 |
| COMPLETENESS | 8 | 14, 15, 18, 19, 20, 21, 23, 24 |
| SHIPPING | 1 | 16 |

25 items in total.

## Suggested order

1 → 2 → 5 → 6+7 (one migration) → 9+10 → 3+4 (one design pass) → 8 → 12 →
13 → 17 → 14 → 18+19 (deletions) → 11 → 25 → 20 → 21 → 24, with 15/16 as an
external track and 22/23 the moment the phone is available.
