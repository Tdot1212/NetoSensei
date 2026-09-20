//
//  NetoSenseiTests.swift
//  NetoSenseiTests
//
//  Created by Tosh Yagishita on 15/12/2025.
//

import Testing
import Foundation
@testable import NetoSensei

struct NetoSenseiTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - Latency Interception Detection (Accuracy audit Phase 2.1)
//
// Pins LatencyInterception.evaluate() against the field calibration data
// measured 2026-06-12 (Guangzhou, CMCC). This is the deterministic stand-in
// for live verification Condition C (V2BOX OFF → MEASURED): that condition
// cannot be reproduced on the dev Mac because the developer is in mainland
// China and the Claude Code session itself depends on the proxy staying up.
// The MEASURED branch these tests exercise is exactly the path Condition C
// would have driven, plus the threshold edges that protect real readings.

struct LatencyInterceptionTests {

    // ---- INTERCEPTED via gateway comparison (Authority 1, pure physics) ----

    @Test func v2boxOn_externalFasterThanGateway_isIntercepted() {
        // Calibration: V2BOX ON external ~1.5ms vs honest ~8.5ms gateway.
        let r = LatencyInterception.evaluate(externalRTTms: 1.5, gatewayRTTms: 8.5, vpnActive: true)
        #expect(r.intercepted == true)
    }

    @Test func liveObservedSamples_areIntercepted() {
        // The two 🔬P21 samples captured live in this session (V2BOX ON).
        let a = LatencyInterception.evaluate(externalRTTms: 0.3, gatewayRTTms: 6.7, vpnActive: false)
        let b = LatencyInterception.evaluate(externalRTTms: 1.7, gatewayRTTms: 5.0, vpnActive: true)
        #expect(a.intercepted == true)  // caught by physics even with vpnActive=false
        #expect(b.intercepted == true)
    }

    // ---- INTERCEPTED via absolute floor (Authority 2, no gateway ref) ----

    @Test func subFloor_noGateway_isIntercepted() {
        // Cellular / gateway unreachable: 1.5ms external with no reference.
        let r = LatencyInterception.evaluate(externalRTTms: 1.5, gatewayRTTms: nil, vpnActive: true)
        #expect(r.intercepted == true)
    }

    // ---- MEASURED: the Condition-C path (V2BOX OFF, real network) ----

    @Test func v2boxOff_realDomestic_isMeasured() {
        // Calibration: V2BOX OFF external 14.8ms (AliDNS) vs ~8.5ms gateway.
        let r = LatencyInterception.evaluate(externalRTTms: 14.8, gatewayRTTms: 8.5, vpnActive: false)
        #expect(r.intercepted == false)
    }

    @Test func realReading_noGateway_isMeasured() {
        let r = LatencyInterception.evaluate(externalRTTms: 14.8, gatewayRTTms: nil, vpnActive: false)
        #expect(r.intercepted == false)
    }

    // ---- MEASURED: threshold edges that must NOT false-positive ----

    @Test func wellPeeredAnycast_3to5ms_notFlaggedAlone() {
        // Task constraint: well-peered AliDNS can legitimately hit 3-5ms; the
        // floor must not flag it on RTT alone (no gateway reference present).
        #expect(LatencyInterception.evaluate(externalRTTms: 3.5, gatewayRTTms: nil, vpnActive: false).intercepted == false)
        #expect(LatencyInterception.evaluate(externalRTTms: 5.0, gatewayRTTms: nil, vpnActive: false).intercepted == false)
    }

    @Test func nearGatewayWithinMargin_isMeasured() {
        // 7.5ms external just under an 8ms gateway: the 1ms jitter margin must
        // keep an honest near-gateway reading from being flagged.
        let r = LatencyInterception.evaluate(externalRTTms: 7.5, gatewayRTTms: 8.0, vpnActive: false)
        #expect(r.intercepted == false)
    }

    @Test func vpnActiveAlone_doesNotFlipHonestReading() {
        // vpn-active must be corroboration only — never sufficient alone.
        let r = LatencyInterception.evaluate(externalRTTms: 25.0, gatewayRTTms: nil, vpnActive: true)
        #expect(r.intercepted == false)
    }

    @Test func vpnActiveWithRealReadingAboveGateway_isMeasured() {
        // VPN on, but the probe path is honest (external 30ms > 8ms gateway).
        let r = LatencyInterception.evaluate(externalRTTms: 30.0, gatewayRTTms: 8.0, vpnActive: true)
        #expect(r.intercepted == false)
    }
}

// MARK: - Speed Test Honesty (Accuracy audit Phase 3)
//
// Pins the two pure decision functions extracted from SpeedTestEngine: the
// packet-loss consistency rule and the interception-aware ping verdict.
// Reproduces the live device bug (Ping 999 / Loss 100% next to 71 Mbps) and
// proves it can no longer be produced.

struct SpeedTestHonestyTests {

    // ---- Packet loss: self-refuting 100% is eliminated ----

    @Test func totalProbeFailure_yieldsNilNotHundredPercent() {
        // The live bug: 10 rounds, 0 succeeded. Old code -> 100%. Now -> nil.
        #expect(SpeedTestEngine.packetLossPercent(roundsRun: 10, successCount: 0) == nil)
    }

    @Test func zeroRounds_isNil() {
        #expect(SpeedTestEngine.packetLossPercent(roundsRun: 0, successCount: 0) == nil)
    }

    @Test func honestLoss_twoOfTenFailed_isTwentyPercent() {
        // 8 of 10 rounds reached the network -> 20% loss, a real measurement.
        #expect(SpeedTestEngine.packetLossPercent(roundsRun: 10, successCount: 8) == 20.0)
    }

    @Test func zeroLoss_allRoundsSucceeded_isZeroNotNil() {
        // A reachable path with no loss reports 0% (a real measurement), not nil.
        #expect(SpeedTestEngine.packetLossPercent(roundsRun: 10, successCount: 10) == 0.0)
    }

    @Test func packetLoss_neverProducesSentinel() {
        // Sweep all (rounds, success) combinations — no output is ever 999, and
        // 100 only never appears because total failure maps to nil.
        for rounds in 0...12 {
            for success in 0...rounds {
                let loss = SpeedTestEngine.packetLossPercent(roundsRun: rounds, successCount: success)
                #expect(loss != 999)
                if success == 0 { #expect(loss == nil) }       // never a self-refuting 100
                else { #expect(loss != nil && loss! < 100) }    // a reached path is < 100% loss
            }
        }
    }

    // ---- Ping: sentinel elimination + interception exclusion ----

    @Test func noSamples_pingIsNilNotNineNineNine() {
        // The live bug: all latency samples failed. Old code -> 999.0. Now -> nil.
        let v = SpeedTestEngine.pingVerdict(samplesMs: [], gatewayRTTms: 8.0, vpnActive: true)
        #expect(v.ping == nil)
        #expect(v.jitter == nil)
        #expect(v.intercepted == false)
    }

    @Test func interceptedSamples_excludedFromPing() {
        // V2BOX-style local stub: ~1ms median vs ~8ms gateway -> intercepted,
        // ping/jitter nil (never the fabricated 1ms), flag raised.
        let v = SpeedTestEngine.pingVerdict(samplesMs: [1.2, 1.5, 1.1, 1.7], gatewayRTTms: 8.0, vpnActive: true)
        #expect(v.ping == nil)
        #expect(v.jitter == nil)
        #expect(v.intercepted == true)
    }

    @Test func honestSamples_realMedianAndJitter() {
        // Real readings above the gateway -> median ping + computed jitter.
        let v = SpeedTestEngine.pingVerdict(samplesMs: [14.0, 16.0, 15.0, 18.0, 15.0], gatewayRTTms: 8.0, vpnActive: false)
        #expect(v.intercepted == false)
        #expect(v.ping == 15.0)          // median of the sorted samples
        #expect((v.jitter ?? 0) > 0)     // real variance present
    }

    @Test func honestSamples_noGatewayRef_stillMeasured() {
        // No gateway reference, plausible RTT (> 2ms floor) -> measured.
        let v = SpeedTestEngine.pingVerdict(samplesMs: [22.0, 25.0, 24.0], gatewayRTTms: nil, vpnActive: false)
        #expect(v.intercepted == false)
        #expect(v.ping == 24.0)
    }
}

// MARK: - Trends Honesty (Accuracy audit Phase 4)
//
// Pins TrendAnalyzer segmentation and the legacy-record migration against
// synthetic histories. Reproduces the live device bug ("Down 93% (7 vs 122
// Mbps)": 122 Mbps Wi-Fi compared against 7 Mbps cellular+VPN) and proves it
// can no longer be produced.

struct TrendsHonestyTests {

    // ---- Fixtures ----

    static let base = Date(timeIntervalSince1970: 1_750_000_000)

    /// Record `i` (higher i = newer). Defaults describe home Wi-Fi, no VPN.
    static func speed(_ i: Int, down: Double, ping: Double? = 20, loss: Double? = 0,
                      type: String = "WiFi", vpn: Bool = false,
                      ssid: String? = "HomeNet", subnet: String? = "192.168.1") -> SpeedTestResult {
        var r = SpeedTestResult(downloadSpeed: down, uploadSpeed: down / 4, ping: ping,
                                jitter: ping.map { _ in 2 }, packetLoss: loss, testDuration: 0,
                                connectionType: type, vpnActive: vpn,
                                networkSSID: ssid, localSubnet: subnet)
        r.timestamp = base.addingTimeInterval(Double(i) * 600)
        return r
    }

    static func titles(_ insights: [TrendAnalyzer.TrendInsight]) -> [String] { insights.map(\.title) }
    static func metrics(_ insights: [TrendAnalyzer.TrendInsight]) -> Set<String> { Set(insights.map(\.metric)) }

    // ---- Segment key shape ----

    @Test func segmentKey_wifiIncludesSSIDAndSubnet_cellularDoesNot() {
        #expect(NetworkSegment.key(connectionType: "WiFi", vpnActive: false, ssid: "HomeNet", subnet: "192.168.1")
                == "WiFi|direct|HomeNet|192.168.1")
        // Cellular: carrier-assigned /24 is not an identity; SSID doesn't exist.
        #expect(NetworkSegment.key(connectionType: "Cellular", vpnActive: true, ssid: nil, subnet: "10.32.7")
                == "Cellular|vpn|-")   // Commit 5: type|vpn|country, "-" when the country is unknown
        // Legacy records (no identity fields) get the coarse key, never a guess.
        #expect(NetworkSegment.key(connectionType: "WiFi", vpnActive: false, ssid: nil, subnet: nil)
                == "WiFi|direct|-|-")
        #expect(NetworkSegment.subnet(of: "192.168.1.42") == "192.168.1")
        #expect(NetworkSegment.subnet(of: "fe80::1") == nil)
        #expect(NetworkSegment.subnet(of: nil) == nil)
    }

    // ---- Same segment: a real trend is still detected ----

    @Test func sameSegment_downloadDrop_isDetected() {
        // 3 earlier tests ~120 Mbps, 3 recent ~60 Mbps, all on the same Wi-Fi.
        let h = [Self.speed(0, down: 120), Self.speed(1, down: 118), Self.speed(2, down: 122),
                 Self.speed(3, down: 60), Self.speed(4, down: 58), Self.speed(5, down: 62)]
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        let drop = insights.first { $0.metric == "download" }
        #expect(drop != nil)
        #expect(drop?.severity == .negative)
        #expect((drop?.changePercent ?? 0) < -20)
        #expect(!Self.metrics(insights).contains(TrendAnalyzer.networkChangedMetric))
    }

    // ---- The live bug: cross-segment pair emits NO delta ----

    @Test func crossSegment_wifiThenCellularVPN_emitsNoDelta() {
        // 122 Mbps home Wi-Fi ×3, then 7 Mbps cellular+VPN ×3 (newest).
        let h = [Self.speed(0, down: 122), Self.speed(1, down: 121), Self.speed(2, down: 123),
                 Self.speed(3, down: 7, ping: 180, type: "Cellular", vpn: true, ssid: nil, subnet: "10.32.7"),
                 Self.speed(4, down: 7, ping: 175, type: "Cellular", vpn: true, ssid: nil, subnet: "10.32.8"),
                 Self.speed(5, down: 8, ping: 190, type: "Cellular", vpn: true, ssid: nil, subnet: "10.32.9")]
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        // Old code: "Download speed dropped — Down 93%". Now: nothing about download or latency.
        #expect(!Self.metrics(insights).contains("download"))
        #expect(!Self.metrics(insights).contains("latency"))
        #expect(!Self.metrics(insights).contains("packetLoss"))
    }

    @Test func networkChange_emitsNeutralLine_onlyRightAfterTheSwitch() {
        // Newest is cellular, the one before is Wi-Fi → neutral "Network changed".
        let switched = [Self.speed(0, down: 120), Self.speed(1, down: 120),
                        Self.speed(2, down: 7, type: "Cellular", vpn: true, ssid: nil, subnet: nil)]
        let a = TrendAnalyzer.analyzeSpeedTrends(history: switched)
        #expect(a.count == 1)
        #expect(a.first?.metric == TrendAnalyzer.networkChangedMetric)
        #expect(a.first?.severity == .neutral)

        // One more test on cellular → the line clears (still no delta: 2 samples).
        let settled = switched + [Self.speed(3, down: 7, type: "Cellular", vpn: true, ssid: nil, subnet: nil)]
        let b = TrendAnalyzer.analyzeSpeedTrends(history: settled)
        #expect(b.isEmpty)
    }

    // ---- Mixed history: only the current network is compared ----

    @Test func mixedHistory_segmentsCorrectly() {
        // Interleaved: Wi-Fi decaying 120 → 60 while cellular is wildly different.
        // Newest is Wi-Fi. The Wi-Fi drop must be found; cellular must be ignored.
        var h: [SpeedTestResult] = []
        let wifi: [Double] = [120, 118, 122, 60, 58, 62]
        for (i, d) in wifi.enumerated() {
            h.append(Self.speed(i * 2, down: d))
            h.append(Self.speed(i * 2 + 1, down: 900, ping: 5, type: "Cellular", ssid: nil, subnet: nil))
        }
        h.append(Self.speed(100, down: 61))  // newest: Wi-Fi
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        let drop = insights.first { $0.metric == "download" }
        #expect(drop?.severity == .negative)
        // Within the Wi-Fi segment the 3 newest are (61, 62, 58) and the next 3
        // are (60, 122, 118): mean 60.3 vs 100 → about −40%.
        #expect((drop?.changePercent ?? 0) < -30)
        #expect(!(drop?.description.contains("900") ?? true))
    }

    // ---- Insufficient same-segment samples → silence ----

    @Test func insufficientSameSegmentSamples_emitsNothing() {
        // 5 Wi-Fi + 10 cellular. Old code (15 records) would have compared
        // whatever 6 were newest. Now Wi-Fi has 5 < 6 → nothing.
        var h: [SpeedTestResult] = []
        for i in 0..<10 { h.append(Self.speed(i, down: 5, type: "Cellular", ssid: nil, subnet: nil)) }
        for i in 10..<15 { h.append(Self.speed(i, down: 100 - Double(i - 10) * 15)) }
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        #expect(insights.isEmpty)
    }

    @Test func legacyCoarseRecords_neverMergeWithIdentifiedRecords() {
        // 3 pre-Phase-4 Wi-Fi records (no SSID/subnet) + 3 identified Wi-Fi
        // records. Same connectionType/vpn, but we do not invent identity:
        // different segments → no delta, and no "network changed" either
        // once the identified run has ≥2 records.
        let h = [Self.speed(0, down: 120, ssid: nil, subnet: nil),
                 Self.speed(1, down: 120, ssid: nil, subnet: nil),
                 Self.speed(2, down: 120, ssid: nil, subnet: nil),
                 Self.speed(3, down: 40), Self.speed(4, down: 40), Self.speed(5, down: 40)]
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        #expect(insights.isEmpty)
    }

    // ---- Latency delta respects segments (closes the referenceLatencyMs gap) ----

    @Test func latencyDelta_sameSegmentDetected_crossSegmentNot() {
        let same = [Self.speed(0, down: 100, ping: 20), Self.speed(1, down: 100, ping: 22), Self.speed(2, down: 100, ping: 18),
                    Self.speed(3, down: 100, ping: 60), Self.speed(4, down: 100, ping: 58), Self.speed(5, down: 100, ping: 62)]
        #expect(Self.metrics(TrendAnalyzer.analyzeSpeedTrends(history: same)).contains("latency"))

        let cross = [Self.speed(0, down: 100, ping: 20), Self.speed(1, down: 100, ping: 22), Self.speed(2, down: 100, ping: 18),
                     Self.speed(3, down: 100, ping: 60, vpn: true), Self.speed(4, down: 100, ping: 58, vpn: true), Self.speed(5, down: 100, ping: 62, vpn: true)]
        #expect(!Self.metrics(TrendAnalyzer.analyzeSpeedTrends(history: cross)).contains("latency"))
    }

    @Test func referenceLatencyFilter_usesSegmentRecentValue() {
        let same = [Self.speed(0, down: 100, ping: 20), Self.speed(1, down: 100, ping: 22), Self.speed(2, down: 100, ping: 18),
                    Self.speed(3, down: 100, ping: 60), Self.speed(4, down: 100, ping: 58), Self.speed(5, down: 100, ping: 62)]
        // Live reference agrees with the 60ms recent average → kept.
        let kept = TrendAnalyzer.allInsights(speedHistory: same, diagnosticHistory: [], referenceLatencyMs: 55)
        #expect(Self.metrics(kept).contains("latency"))
        // Live reference wildly disagrees → suppressed.
        let dropped = TrendAnalyzer.allInsights(speedHistory: same, diagnosticHistory: [], referenceLatencyMs: 400)
        #expect(!Self.metrics(dropped).contains("latency"))
    }

    @Test func packetLossFrequency_isSegmentScoped() {
        // 3 lossy cellular tests then 2 clean Wi-Fi tests (newest Wi-Fi):
        // old code counted 3 of last 5 → "Frequent packet loss". Now Wi-Fi only.
        let h = [Self.speed(0, down: 5, loss: 8, type: "Cellular", ssid: nil, subnet: nil),
                 Self.speed(1, down: 5, loss: 6, type: "Cellular", ssid: nil, subnet: nil),
                 Self.speed(2, down: 5, loss: 9, type: "Cellular", ssid: nil, subnet: nil),
                 Self.speed(3, down: 100, loss: 0), Self.speed(4, down: 100, loss: 0)]
        #expect(!Self.metrics(TrendAnalyzer.analyzeSpeedTrends(history: h)).contains("packetLoss"))
    }

    @Test func windowMeans_requireMeasuredValuesOnBothSides() {
        #expect(TrendAnalyzer.windowMeans(recent: [nil, nil, nil], earlier: [20, 22, 18]) == nil)
        #expect(TrendAnalyzer.windowMeans(recent: [30, nil, 30], earlier: [nil, nil, nil]) == nil)
        #expect(TrendAnalyzer.windowMeans(recent: [30, nil, 30], earlier: [0, 0, 0]) == nil)   // ratio vs 0
        let m = TrendAnalyzer.windowMeans(recent: [30, nil, 30], earlier: [20, 22, 18])
        #expect(m?.recent == 30 && m?.earlier == 20)
    }

    // ---- Diagnostic trends: same network only ----

    @Test func diagnosticTrends_recurringIssue_isSegmentScoped() {
        func diag(_ i: Int, issues: Int, cat: String, type: String?, vpn: Bool?, ssid: String?) -> DiagnosticHistoryEntry {
            DiagnosticHistoryEntry(timestamp: Self.base.addingTimeInterval(Double(i) * 600), summary: "", issueCount: issues,
                                   primaryIssueCategory: cat, overallStatus: "green",
                                   connectionType: type, vpnActive: vpn, networkSSID: ssid, localSubnet: nil)
        }
        // 3 DNS failures on hotel Wi-Fi, then 2 clean runs at home (newest).
        let h = [diag(0, issues: 2, cat: "DNS", type: "WiFi", vpn: false, ssid: "Hotel"),
                 diag(1, issues: 2, cat: "DNS", type: "WiFi", vpn: false, ssid: "Hotel"),
                 diag(2, issues: 2, cat: "DNS", type: "WiFi", vpn: false, ssid: "Hotel"),
                 diag(3, issues: 0, cat: "None", type: "WiFi", vpn: false, ssid: "HomeNet"),
                 diag(4, issues: 0, cat: "None", type: "WiFi", vpn: false, ssid: "HomeNet")]
        let insights = TrendAnalyzer.analyzeDiagnosticTrends(history: h)
        // Old code: "DNS issues recurring" AND "Connection stability improved" — both
        // artifacts of the network change. Now: nothing.
        #expect(insights.isEmpty)

        // Legacy entries (nil identity) never merge with identified ones.
        let legacy = [diag(0, issues: 3, cat: "DNS", type: nil, vpn: nil, ssid: nil),
                      diag(1, issues: 3, cat: "DNS", type: nil, vpn: nil, ssid: nil),
                      diag(2, issues: 3, cat: "DNS", type: nil, vpn: nil, ssid: nil),
                      diag(3, issues: 0, cat: "None", type: "WiFi", vpn: false, ssid: "HomeNet")]
        #expect(TrendAnalyzer.analyzeDiagnosticTrends(history: legacy).isEmpty)
    }

    // ---- Legacy records: decode + migration ----

    static let legacyJSON = """
    [{"id":"11111111-1111-1111-1111-111111111111","timestamp":700000000,
      "downloadSpeed":71.1,"uploadSpeed":75.4,"ping":999,"jitter":0,"packetLoss":100,
      "testDuration":0,"connectionType":"Cellular","vpnActive":true,"quality":"Poor"},
     {"id":"22222222-2222-2222-2222-222222222222","timestamp":700000600,
      "downloadSpeed":97,"uploadSpeed":79.8,"ping":14.8,"jitter":1.2,"packetLoss":20,
      "testDuration":0,"connectionType":"WiFi","vpnActive":false,"quality":"Good"}]
    """.data(using: .utf8)!

    @Test func prePhase3Records_stillDecode() throws {
        // Phase 3 added `latencyIntercepted` (non-optional, defaulted). Synthesized
        // Decodable ignores defaults → the whole array failed → history wiped.
        let records = try JSONDecoder().decode([SpeedTestResult].self, from: Self.legacyJSON)
        #expect(records.count == 2)
        #expect(records[0].latencyIntercepted == false)
        #expect(records[0].networkSSID == nil && records[0].localSubnet == nil)
        #expect(records[0].ping == 999)          // raw sentinel survives decode…
        #expect(records[0].segmentKey == "Cellular|vpn|-")
    }

    @Test func migration_stripsSentinels_recomputesQuality_leavesHonestValues() throws {
        let records = try JSONDecoder().decode([SpeedTestResult].self, from: Self.legacyJSON)
        let out = LegacySpeedRecordMigration.apply(records)
        #expect(out.changedCount == 1)
        let fixed = out.records[0]
        #expect(fixed.ping == nil)               // …and is nil after migration
        #expect(fixed.jitter == nil)             // jitter follows ping (Phase 3 contract)
        #expect(fixed.packetLoss == nil)         // 100% next to 71 Mbps was never a measurement
        #expect(fixed.quality != .poor)          // rating no longer derived from the sentinel
        #expect(fixed.id == records[0].id && fixed.timestamp == records[0].timestamp)
        // The honest record is untouched: 14.8 ms ping and a real 20% loss stay.
        let honest = out.records[1]
        #expect(honest.ping == 14.8 && honest.packetLoss == 20 && honest.quality == .good)
    }

    @Test func migration_isIdempotent_secondRunIsNoOp() throws {
        let records = try JSONDecoder().decode([SpeedTestResult].self, from: Self.legacyJSON)
        let first = LegacySpeedRecordMigration.apply(records)
        let second = LegacySpeedRecordMigration.apply(first.records)
        #expect(first.changedCount == 1)
        #expect(second.changedCount == 0)
        #expect(second.records.map(\.ping) == first.records.map(\.ping))
        #expect(second.records.map(\.packetLoss) == first.records.map(\.packetLoss))
    }

    @Test func migratedSentinelRecords_areExcludedFromTrends() throws {
        // 6 same-network records; the 3 earlier ones carry the 999 sentinel.
        // Before migration the sentinel would have driven a bogus "latency
        // improved" delta; after migration the earlier window has no measured
        // ping → no latency insight at all.
        var h: [SpeedTestResult] = []
        for i in 0..<3 { h.append(Self.speed(i, down: 100, ping: 999)) }
        for i in 3..<6 { h.append(Self.speed(i, down: 100, ping: 20)) }
        #expect(Self.metrics(TrendAnalyzer.analyzeSpeedTrends(history: h)).contains("latency"))  // sentinel = garbage
        let migrated = LegacySpeedRecordMigration.apply(h).records
        #expect(!Self.metrics(TrendAnalyzer.analyzeSpeedTrends(history: migrated)).contains("latency"))
    }

    // ---- NetworkHistoryEntry.latency: optional, legacy 0 → nil, nil-safe averages ----

    @Test func networkHistoryEntry_legacyZeroLatency_decodesAsNil() throws {
        let json = """
        [{"id":"33333333-3333-3333-3333-333333333333","timestamp":"2026-06-12T10:00:00Z","healthScore":80,
          "latency":0,"gatewayLatency":6.6,"dnsLatency":12,"vpnActive":true,"rootCause":"Speed Test","connectionType":"WiFi"},
         {"id":"44444444-4444-4444-4444-444444444444","timestamp":"2026-06-12T10:10:00Z","healthScore":90,
          "latency":42.5,"gatewayLatency":6.1,"dnsLatency":11,"vpnActive":false,"rootCause":"Speed Test","connectionType":"WiFi"},
         {"id":"55555555-5555-5555-5555-555555555555","timestamp":"2026-06-12T10:20:00Z","healthScore":90,
          "gatewayLatency":6.1,"dnsLatency":11,"vpnActive":false,"rootCause":"Speed Test","connectionType":"WiFi"}]
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([NetworkHistoryEntry].self, from: json)
        #expect(entries[0].latency == nil)     // the `?? 0` write → nil
        #expect(entries[1].latency == 42.5)    // a real reading survives
        #expect(entries[2].latency == nil)     // key absent → nil
        // Averages skip nil rather than diluting with 0.
        #expect(NetworkHistoryEntry.averageLatency(of: entries) == 42.5)
        #expect(NetworkHistoryEntry.averageLatency(of: [entries[0], entries[2]]) == nil)
    }

    @Test func networkHistoryEntry_averageSkipsNil() {
        func e(_ latency: Double?) -> NetworkHistoryEntry {
            NetworkHistoryEntry(healthScore: 80, downloadSpeed: nil, uploadSpeed: nil, latency: latency,
                                gatewayLatency: 5, dnsLatency: 10, jitter: nil, packetLoss: nil,
                                vpnActive: false, vpnOverhead: nil, rootCause: "Speed Test", connectionType: "WiFi")
        }
        #expect(NetworkHistoryEntry.averageLatency(of: [e(30), e(nil), e(50), e(nil)]) == 40)
        #expect(NetworkHistoryEntry.averageLatency(of: [e(nil), e(nil)]) == nil)
        #expect(NetworkHistoryEntry.averageLatency(of: []) == nil)
    }
}

// MARK: - Default route resolver (Diagnosis v2, Commit 1)
//
// The simulator shares the host's kernel routing table, so this exercises the
// real sysctl parser. It asserts structural validity, not a specific address:
// every parsed route must be a dotted IPv4 gateway on a named interface, and
// the LAN pick (if any) must be on a physical en* interface — never a tunnel.

struct DefaultRouteResolverTests {

    @Test func parsedRoutes_areWellFormed() {
        let routes = DefaultRouteResolver.ipv4DefaultRoutes()
        for r in routes {
            let octets = r.gateway.split(separator: ".")
            #expect(octets.count == 4, "gateway must be dotted IPv4: \(r.gateway)")
            #expect(octets.allSatisfy { UInt8($0) != nil }, "octets must be 0–255: \(r.gateway)")
            #expect(r.gateway != "0.0.0.0")
            #expect(!r.interface.isEmpty)
        }
    }

    @Test func lanGateway_isNeverATunnelOrCellularInterface() {
        if let lan = DefaultRouteResolver.lanGateway() {
            #expect(lan.interface.hasPrefix("en"))
            #expect(!lan.interface.hasPrefix("utun"))
            #expect(!lan.interface.hasPrefix("pdp_ip"))
            #expect(DefaultRouteResolver.ipv4DefaultRoutes().contains(lan))
        }
        // No LAN default route (e.g. a host with only a tunnel) is a valid nil, not a guess.
    }
}

// MARK: - Verdict composer (Diagnosis v2, Commit 2)
//
// Pins the composer rules from the design (§B): a failed check is never a
// pass; the score is nil below the coverage floor; state derives from findings
// so the number and the word cannot disagree; not-applicable is excluded from
// counts; nothing is estimated (VPN overhead only when both delays ran).

struct VerdictComposerTests {

    static let wifiDirect = VerdictContext(connectionType: "WiFi", vpn: .off)
    static let wifiVPN = VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: true, exitCountry: "US"))
    static let cellular = VerdictContext(connectionType: "Cellular", vpn: .off)

    // ---- Vocabulary edges are pinned (§D) ----

    @Test func bands_edgesArePinned() {
        #expect(MetricBands.score(80) == .excellent && MetricBands.score(79) == .good)
        #expect(MetricBands.score(60) == .good && MetricBands.score(40) == .fair && MetricBands.score(20) == .poor && MetricBands.score(19) == .critical)
        #expect(MetricBands.gatewayDelay(ms: 9.9) == .excellent && MetricBands.gatewayDelay(ms: 100) == .critical)
        #expect(MetricBands.internetDelay(ms: 300, viaVPN: false) == .critical)
        #expect(MetricBands.internetDelay(ms: 300, viaVPN: true) == .fair)     // a working tunnel is not "critical"
        #expect(MetricBands.dnsDelay(ms: 299) == .poor && MetricBands.dnsDelay(ms: 300) == .critical)
        #expect(MetricBands.packetLoss(percent: 0.4) == .excellent && MetricBands.packetLoss(percent: 10) == .critical)
        #expect(MetricBands.downloadSpeed(mbps: 50) == .excellent && MetricBands.downloadSpeed(mbps: 4.9) == .critical)
        #expect(Band.excellent.word == "Excellent" && Band.critical.word == "Critical")
    }

    // ---- B1: a failed check is never a pass ----

    @Test func singleFailure_isCoverageNotDiagnosis() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"),
            .ran(.externalLatency, 20, unit: "ms"),
            .failed(.dnsResolve, .timeout, streak: 1)
        ], context: Self.wifiDirect)
        #expect(v.score?.value == 100)                                   // no penalty for one timeout
        #expect(!v.findings.contains { $0.kind == .dnsFailing })          // not a diagnosis either
        #expect(v.coverage.line.contains("2 of 3 checks completed"))
        #expect(v.coverage.line.contains("address lookup timed out"))
        #expect(v.state == .working)
        #expect(v.headline == "Working normally in the checks that completed")  // never "all checks passed"
    }

    @Test func repeatedFailure_becomesAFinding_neverAPass() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"),
            .ran(.externalLatency, 20, unit: "ms"),
            .failed(.dnsResolve, .timeout, streak: 2)
        ], context: Self.wifiDirect)
        #expect(v.score?.value == 80)
        let f = v.findings.first { $0.kind == .dnsFailing }
        #expect(f != nil && f?.severity == .critical)
        #expect(v.state == .broken)
        if case .userFixable(let steps) = f?.action { #expect(!steps.isEmpty) } else { Issue.record("DNS failure must be user-fixable with steps") }
    }

    // ---- B2: score is nil below the coverage floor ----

    @Test func scoreIsNil_whenInternetDelayNeverRan() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"),
            .failed(.externalLatency, .timeout, streak: 1)
        ], context: Self.wifiDirect)
        #expect(v.score == nil)
        #expect(v.scoreText == "—")
        #expect(v.state == .unknown)
        #expect(v.headline == "Not enough checks completed to judge this connection")
    }

    @Test func notApplicableGateway_satisfiesTheFloor_andIsExcludedFromCounts() {
        let v = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "no router on cellular"),
            .ran(.externalLatency, 45, unit: "ms"),
            .notApplicable(.vpnState, "no VPN in use")
        ], context: Self.cellular)
        #expect(v.score != nil)
        #expect(v.coverage.attempted.count == 1)
        #expect(v.coverage.line.hasPrefix("1 check completed"))
        #expect(v.coverage.line.contains("not applicable — router delay: no router on cellular"))
        #expect(v.state == .working)
    }

    @Test func noInternet_isBroken_withNoNumber() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 5, unit: "ms"),
            .failed(.externalLatency, .timeout, streak: 2),
            .failed(.httpReach, .timeout, streak: 2)
        ], context: Self.wifiDirect)
        #expect(v.score == nil)
        #expect(v.state == .broken)
        #expect(v.primary?.kind == .noInternet)
        #expect(v.headline == "No internet connection")
    }

    // ---- B3: state derives from findings, never from arithmetic ----

    @Test func state_followsFindings_notTheNumber() {
        func f(_ sev: Band, byDesign: Bool = false) -> Finding {
            Finding(kind: .internetSlow, severity: sev, confidence: Confidence(level: .high, reason: ""),
                    headline: "", evidence: [], cause: "", action: .none, basedOn: [], byDesign: byDesign)
        }
        let cov = Coverage(records: [])
        let excellent = Score(value: 90, band: .excellent, basedOn: [])
        let fair = Score(value: 55, band: .fair, basedOn: [])
        #expect(VerdictComposer.deriveState(findings: [f(.poor)], score: excellent, coverage: cov) == .degraded)  // 90 + a poor finding = degraded
        #expect(VerdictComposer.deriveState(findings: [], score: fair, coverage: cov) == .degraded)              // fair number, no finding = still degraded
        #expect(VerdictComposer.deriveState(findings: [f(.critical)], score: excellent, coverage: cov) == .broken)
        #expect(VerdictComposer.deriveState(findings: [], score: nil, coverage: cov) == .unknown)
        #expect(VerdictComposer.deriveState(findings: [], score: excellent, coverage: cov) == .working)
        // By-design findings (roaming backhaul, proxy interception) never make the network "broken".
        #expect(VerdictComposer.deriveState(findings: [f(.critical, byDesign: true)], score: excellent, coverage: cov) == .degraded)
    }

    @Test func healthyNetwork_isWorking_withNoFindings() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"), .ran(.externalLatency, 18, unit: "ms"),
            .ran(.dnsLatency, 12, unit: "ms"), .ran(.dnsResolve, 1, unit: ""), .ran(.httpReach, 1, unit: "")
        ], context: Self.wifiDirect)
        #expect(v.score?.value == 100 && v.score?.band == .excellent)
        #expect(v.findings.isEmpty && v.primary == nil)
        #expect(v.state == .working)
        #expect(v.headline == "Your connection is working normally")
        #expect(v.coverage.line == "All 5 checks completed")
    }

    @Test func slowInternet_direct_isADegradedFindingWithEvidenceCauseAndAction() {
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"), .ran(.externalLatency, 220, unit: "ms")
        ], context: Self.wifiDirect)
        #expect(v.state == .degraded)
        let f = v.primary
        // Router fine + VPN off + slow internet is the E5 provider pattern (commit 3);
        // the generic internetSlow finding is the fallback when no pattern claims it.
        #expect((f?.kind == .ispSlow || f?.kind == .internetSlow) && f?.severity == .poor)
        #expect(f?.evidence.contains { $0.text.hasPrefix("Internet delay: 220 ms (poor)") } == true)
        #expect(f?.cause.isEmpty == false)
        #expect(f?.action != Action.none)
        // Headline rule: no jargon tokens.
        for banned in ["latency", "jitter", "DNS", "gateway", "packet", "RTT", "ms", "ISP"] {
            #expect(!(f?.headline.contains(banned) ?? false), "headline contains jargon: \(banned)")
        }
    }

    // ---- B5: nothing is estimated ----

    @Test func vpnOverhead_isOnlyChargedWhenBothDelaysRan() {
        // Gateway not applicable (hidden by VPN): no `ext − 30` guess, no overhead term.
        let noGateway = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "hidden by VPN"), .ran(.externalLatency, 400, unit: "ms")
        ], context: Self.wifiVPN)
        #expect(noGateway.score?.value == 82)   // 100 − 18 (VPN scale, > 250) and nothing else
        // Gateway ran: overhead 396 ms is measured and charged once.
        let withGateway = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 4, unit: "ms"), .ran(.externalLatency, 400, unit: "ms")
        ], context: Self.wifiVPN)
        #expect(withGateway.score?.value == 72) // 100 − 18 − 10
    }

    @Test func viaVPN_400ms_isFairNotCritical() {
        let v = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "hidden by VPN"), .ran(.externalLatency, 380, unit: "ms")
        ], context: Self.wifiVPN)
        // On the direct scale 380 ms would be "critical"; via VPN it is fair → no finding, still working.
        #expect(!v.findings.contains { $0.kind == .internetSlow })
        #expect(v.state == .working)
    }

    @Test func coverageLine_neverClaimsUnrunChecks() {
        let cov = Coverage(records: [
            .ran(.externalLatency, 30, unit: "ms"),
            .failed(.dnsHijack, .timeout),
            .notRun(.vpnLeak, "Deep Scan only")
        ])
        #expect(cov.line == "1 of 2 checks completed · 1 couldn't run — DNS hijack test timed out")
    }
}

// MARK: - Named patterns (Diagnosis v2, Commit 3)
//
// Each pattern's detection signature against synthetic check records, plus
// the §C contract: plain headline, evidence, cause, exactly one action. The
// cellular pair (tower congestion / roaming backhaul) is mutually exclusive
// by signature and must be honest that iOS exposes no signal strength.

struct VerdictPatternTests {

    static func oneAction(_ f: Finding?) -> Bool { f != nil }
    static func isNotFixable(_ f: Finding?) -> Bool { if case .notFixable = f?.action { return true } else { return false } }
    static func isUserFixable(_ f: Finding?) -> Bool { if case .userFixable(let s) = f?.action { return !s.isEmpty } else { return false } }
    static func isElsewhere(_ f: Finding?) -> String? { if case .fixableElsewhere(let who, _, _) = f?.action { return who } else { return nil } }

    // ---- E1 tower congestion ----

    @Test func towerCongestion_cellularSlowAndUnsteady_isNotFixable_andHonestAboutSignal() {
        let ctx = VerdictContext(connectionType: "Cellular", vpn: .off, radioTechnology: "5G")
        let v = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "no router on cellular"),
            .ran(.externalLatency, 320, unit: "ms"), .ran(.jitter, 85, unit: "ms"),
            .ran(.throughput, 2.1, unit: "Mbps"), .ran(.packetLoss, 4, unit: "%")
        ], context: ctx)
        let f = v.primary
        #expect(f?.kind == .towerCongestion)
        #expect(Self.isNotFixable(f))
        #expect(f?.byDesign == true && v.state == .degraded)                 // never "broken"
        #expect(f?.confidence.level == .medium)
        #expect(f?.confidence.reason.contains("does not let apps read cellular signal strength") == true)
        #expect(f?.evidence.count == 4)
        if case .notFixable(_, let expect, let workarounds) = f?.action { #expect(!expect.isEmpty && workarounds.count >= 2) }
        // The generic loss/jitter findings must not double-report the same checks.
        #expect(!v.findings.contains { $0.kind == .packetLossHigh || $0.kind == .jitterHigh || $0.kind == .internetSlow })
    }

    @Test func towerCongestion_requiresAJitterReading() {
        // Slow cellular without a steadiness reading cannot be told from a distant route → generic finding, jitter listed as sharpening.
        let v = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "no router on cellular"), .ran(.externalLatency, 320, unit: "ms")
        ], context: VerdictContext(connectionType: "Cellular", vpn: .off))
        #expect(!v.findings.contains { $0.kind == .towerCongestion })
        #expect(v.primary?.kind == .internetSlow)
    }

    // ---- E2 roaming SIM backhaul ----

    @Test func roamingSIM_cellularSteadyFarExitCountryMismatch_isNotFixable() {
        let ctx = VerdictContext(connectionType: "Cellular", vpn: .off, publicCountry: "CN", expectedCountry: "US", publicIPVerified: true)
        let v = VerdictComposer.compose(records: [
            .notApplicable(.gatewayLatency, "no router on cellular"),
            .ran(.externalLatency, 296, unit: "ms"), .ran(.jitter, 8, unit: "ms")
        ], context: ctx)
        let f = v.primary
        #expect(f?.kind == .roamingSIMBackhaul)
        #expect(Self.isNotFixable(f) && f?.byDesign == true)
        #expect(f?.confidence.level == .high)
        #expect(f?.cause.contains("CN") == true && f?.cause.contains("US") == true)
        if case .notFixable(_, _, let w) = f?.action { #expect(w.contains { $0.contains("eSIM") }) }
        #expect(!v.findings.contains { $0.kind == .towerCongestion })       // mutually exclusive
    }

    @Test func roamingSIM_isSuppressed_byVPN_bySameRegion_byUnsteadyDelay() {
        let base: [CheckRecord] = [.notApplicable(.gatewayLatency, "no router on cellular"), .ran(.externalLatency, 296, unit: "ms"), .ran(.jitter, 8, unit: "ms")]
        // VPN on: the IP country is the exit, not the SIM.
        let vpn = VerdictContext(connectionType: "Cellular", vpn: .on(authoritative: true, exitCountry: "US"), publicCountry: "US", expectedCountry: "CN")
        #expect(!VerdictComposer.compose(records: base, context: vpn).findings.contains { $0.kind == .roamingSIMBackhaul })
        // HK exit while in CN is the same region group.
        let hk = VerdictContext(connectionType: "Cellular", vpn: .off, publicCountry: "HK", expectedCountry: "CN")
        #expect(!VerdictComposer.compose(records: base, context: hk).findings.contains { $0.kind == .roamingSIMBackhaul })
        // Unsteady delay is E1's territory, not E2's.
        let unsteady: [CheckRecord] = [.notApplicable(.gatewayLatency, "no router on cellular"), .ran(.externalLatency, 296, unit: "ms"), .ran(.jitter, 90, unit: "ms")]
        let ctx = VerdictContext(connectionType: "Cellular", vpn: .off, publicCountry: "CN", expectedCountry: "US")
        let v = VerdictComposer.compose(records: unsteady, context: ctx)
        #expect(!v.findings.contains { $0.kind == .roamingSIMBackhaul })
        #expect(v.findings.contains { $0.kind == .towerCongestion })
    }

    // ---- E3 proxy interception ----

    @Test func proxyInterception_explainsMissingNumbers_byDesign() {
        let ctx = VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: false, exitCountry: nil), latencyIntercepted: true)
        let v = VerdictComposer.compose(records: [
            .ran(.gatewayLatency, 5, unit: "ms"), .failed(.externalLatency, .intercepted)
        ], context: ctx)
        let f = v.findings.first { $0.kind == .proxyInterception }
        #expect(f != nil && f?.byDesign == true && Self.isNotFixable(f))
        #expect(v.score == nil)                                                // no internet delay measured → no number
        #expect(v.state != .broken)
        #expect(v.coverage.line.contains("internet delay was answered by a local VPN/proxy"))
    }

    // ---- E4 VPN overhead vs E5 ISP vs E6 undetermined ----

    @Test func vpnOverhead_routerFineTunnelSlow_isUserFixable_measuredNeverEstimated() {
        let ctx = VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: true, exitCountry: "US"))
        let v = VerdictComposer.compose(records: [.ran(.gatewayLatency, 4, unit: "ms"), .ran(.externalLatency, 335, unit: "ms")], context: ctx)
        let f = v.primary
        #expect(f?.kind == .vpnOverhead && Self.isUserFixable(f))
        #expect(f?.evidence.contains { $0.label == "Added by the VPN" && $0.value == 331 } == true)
        #expect(f?.cause.contains("in US") == true)
        #expect(f?.severity == .fair && v.state == .degraded)
    }

    @Test func ispSlow_routerFineVPNOff_isFixableElsewhere_byTheProvider() {
        let v = VerdictComposer.compose(records: [.ran(.gatewayLatency, 6, unit: "ms"), .ran(.externalLatency, 240, unit: "ms"), .ran(.throughput, 3.2, unit: "Mbps")],
                                        context: VerdictContext(connectionType: "WiFi", vpn: .off))
        let f = v.primary
        #expect(f?.kind == .ispSlow)
        #expect(Self.isElsewhere(f) == "Your internet provider")
        #expect(f?.evidence.count == 3)
        #expect(!v.findings.contains { $0.kind == .internetSlow })            // pattern claims the check; no generic duplicate
    }

    @Test func ispSlow_isNotClaimed_whenTheRouterIsAlsoSlow() {
        // Router 70 ms, internet 240 ms: the local hop is suspect, so the provider is not blamed.
        let v = VerdictComposer.compose(records: [.ran(.gatewayLatency, 70, unit: "ms"), .ran(.externalLatency, 240, unit: "ms")],
                                        context: VerdictContext(connectionType: "WiFi", vpn: .off))
        #expect(!v.findings.contains { $0.kind == .ispSlow })
        #expect(v.findings.contains { $0.kind == .routerSlow })
    }

    @Test func vpnOn_routerHidden_cannotAttribute_saysSo() {
        let ctx = VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: true, exitCountry: "US"))
        let v = VerdictComposer.compose(records: [.notApplicable(.gatewayLatency, "hidden by VPN"), .ran(.externalLatency, 500, unit: "ms")], context: ctx)
        let f = v.findings.first { $0.kind == .vpnOrNetworkUndetermined }
        #expect(f != nil && f?.confidence.level == .low && f?.action == Action.none)
        #expect(f?.wouldSharpen == [.gatewayLatency])
        #expect(!v.findings.contains { $0.kind == .vpnOverhead })              // no `ext − 30` guess, ever
    }

    // ---- E9 captive portal, E10 cross-border, E14 hotspot ----

    @Test func captivePortal_isCriticalAndUserFixable() {
        let v = VerdictComposer.compose(records: [.ran(.captivePortal, 1, unit: ""), .failed(.externalLatency, .blocked, streak: 2), .ran(.gatewayLatency, 3, unit: "ms")],
                                        context: VerdictContext(connectionType: "WiFi", vpn: .off))
        #expect(v.primary?.kind == .captivePortal && Self.isUserFixable(v.primary))
        #expect(v.state == .broken)
    }

    @Test func crossBorder_chinaVPNOff_domesticOKOverseasBlocked_isByDesign() {
        let ctx = VerdictContext(connectionType: "WiFi", vpn: .off, likelyInChina: true)
        let v = VerdictComposer.compose(records: [.ran(.gatewayLatency, 3, unit: "ms"), .ran(.externalLatency, 18, unit: "ms"),
                                                  .ran(.domesticReach, 1, unit: ""), .failed(.httpReach, .timeout, streak: 2)], context: ctx)
        let f = v.findings.first { $0.kind == .crossBorderRestriction }
        #expect(f != nil && f?.byDesign == true && Self.isNotFixable(f))
        #expect(!v.findings.contains { $0.kind == .noInternet })              // the web check is explained, not a "no internet"
        #expect(v.state == .degraded)
    }

    @Test func hotspot_isInformational() {
        let v = VerdictComposer.compose(records: [.ran(.gatewayLatency, 30, unit: "ms"), .ran(.externalLatency, 90, unit: "ms")],
                                        context: VerdictContext(connectionType: "WiFi", vpn: .off, isHotspot: true))
        let f = v.findings.first { $0.kind == .hotspotShared }
        #expect(f != nil && f?.action == Action.none && f?.byDesign == true)
    }

    // ---- Every pattern finding honours the §C contract ----

    @Test func everyPatternFinding_hasPlainHeadline_causeAndExactlyOneAction() {
        let cases: [([CheckRecord], VerdictContext)] = [
            ([.notApplicable(.gatewayLatency, "-"), .ran(.externalLatency, 320, unit: "ms"), .ran(.jitter, 85, unit: "ms")], VerdictContext(connectionType: "Cellular", vpn: .off)),
            ([.notApplicable(.gatewayLatency, "-"), .ran(.externalLatency, 296, unit: "ms"), .ran(.jitter, 8, unit: "ms")], VerdictContext(connectionType: "Cellular", vpn: .off, publicCountry: "CN", expectedCountry: "US")),
            ([.ran(.gatewayLatency, 5, unit: "ms"), .failed(.externalLatency, .intercepted)], VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: false, exitCountry: nil), latencyIntercepted: true)),
            ([.ran(.gatewayLatency, 4, unit: "ms"), .ran(.externalLatency, 335, unit: "ms")], VerdictContext(connectionType: "WiFi", vpn: .on(authoritative: true, exitCountry: "US"))),
            ([.ran(.gatewayLatency, 6, unit: "ms"), .ran(.externalLatency, 240, unit: "ms")], VerdictContext(connectionType: "WiFi", vpn: .off)),
            ([.ran(.captivePortal, 1, unit: ""), .ran(.gatewayLatency, 3, unit: "ms"), .failed(.externalLatency, .blocked, streak: 2)], VerdictContext(connectionType: "WiFi", vpn: .off)),
        ]
        let banned = ["latency", "jitter", "DNS", "gateway", "packet", "RTT", " ms", "ISP", "CGNAT", "MITM", "TUN"]
        for (records, ctx) in cases {
            let v = VerdictComposer.compose(records: records, context: ctx)
            #expect(!v.findings.isEmpty)
            for f in v.findings {
                #expect(f.headline.count <= 60, "headline too long: \(f.headline)")
                for b in banned { #expect(!f.headline.contains(b), "jargon '\(b)' in: \(f.headline)") }
                #expect(!f.cause.isEmpty)
                if case .notFixable(let why, let expect, _) = f.action { #expect(!why.isEmpty && !expect.isEmpty) }
                if case .fixableElsewhere(let who, _, _) = f.action { #expect(!who.isEmpty) }
            }
        }
    }
}

// MARK: - Verdict inputs + Trends ordering (Diagnosis v2, Commit 4)

struct VerdictInputsTests {

    static func status(cellular: Bool = false, wifi: Bool = true, gatewayIP: String? = "192.168.1.1",
                       gatewayMs: Double? = 5, externalMs: Double? = 20, intercepted: Bool = false,
                       reachable: Bool = true, dnsMs: Double? = 12, dnsOK: Bool = true, vpn: Bool = false) -> NetworkStatus {
        var s = NetworkStatus.empty
        s.connectionType = cellular ? .cellular : .wifi
        s.wifi.isConnected = wifi
        s.router.gatewayIP = gatewayIP
        s.router.latency = gatewayMs
        s.router.isReachable = gatewayMs != nil
        s.internet.latencyToExternal = externalMs
        s.internet.latencyIntercepted = intercepted
        s.internet.isReachable = reachable
        s.internet.httpTestSuccess = reachable
        s.dns.latency = dnsMs
        s.dns.lookupSuccess = dnsOK
        s.vpn.isActive = vpn
        return s
    }

    @Test func cellularOnly_routerIsNotApplicable_neverFailed() {
        let recs = VerdictInputs.records(from: Self.status(cellular: true, wifi: false, gatewayIP: nil, gatewayMs: nil), streaks: .init())
        let gw = recs.first { $0.id == .gatewayLatency }
        if case .notApplicable = gw?.status {} else { Issue.record("gateway on cellular must be not applicable") }
        #expect(!recs.contains { $0.id == .gatewayReach })
    }

    @Test func interceptedProbe_isASingleExplainedFailure() {
        let recs = VerdictInputs.records(from: Self.status(externalMs: nil, intercepted: true), streaks: .init(external: 3))
        let ext = recs.first { $0.id == .externalLatency }
        #expect(ext?.status == .failed(.intercepted))
        #expect(ext?.consecutiveFailures == 1)              // never promoted to "no internet" by the streak
    }

    @Test func failureStreaks_flowThroughToRecords() {
        let recs = VerdictInputs.records(from: Self.status(gatewayMs: nil, externalMs: nil, reachable: false, dnsMs: nil, dnsOK: false),
                                         streaks: .init(gateway: 2, external: 3, dns: 2))
        #expect(recs.first { $0.id == .gatewayReach }?.consecutiveFailures == 2)
        #expect(recs.first { $0.id == .externalLatency }?.consecutiveFailures == 3)
        #expect(recs.first { $0.id == .dnsResolve }?.consecutiveFailures == 2)
        let v = VerdictComposer.compose(records: recs, context: VerdictContext(connectionType: "WiFi", vpn: .off))
        #expect(v.state == .broken && v.score == nil)
    }

    @Test func vpnHidesRouter_isNotApplicable_notAFailure() {
        let recs = VerdictInputs.records(from: Self.status(gatewayMs: nil, vpn: true), streaks: .init(gateway: 5))
        if case .notApplicable(let why) = recs.first(where: { $0.id == .gatewayLatency })?.status { #expect(why.contains("VPN")) }
        else { Issue.record("router hidden by VPN must be not applicable") }
    }

    @Test func staleOrOtherNetworkSpeedTest_isNotEvidence() {
        var stale = SpeedTestResult(downloadSpeed: 50, uploadSpeed: 10, ping: 20, jitter: 40, packetLoss: 0, testDuration: 0,
                                    connectionType: "WiFi", vpnActive: false, networkSSID: nil, localSubnet: nil)
        stale.timestamp = Date().addingTimeInterval(-3600)
        let recs = VerdictInputs.records(from: Self.status(), streaks: .init(), recentSpeedTest: stale)
        #expect(!recs.contains { $0.id == .throughput })
        // Same segment and fresh → used.
        var fresh = stale
        fresh.timestamp = Date()
        let s = Self.status()
        fresh.networkSSID = s.wifi.ssid
        fresh.localSubnet = NetworkSegment.subnet(of: s.localIP)
        let recs2 = VerdictInputs.records(from: s, streaks: .init(), recentSpeedTest: fresh)
        #expect(recs2.contains { $0.id == .throughput } && recs2.contains { $0.id == .jitter })
    }

    @Test func context_vpnOn_isAuthoritativeAware_andCellularKeepsRadio() {
        let s = Self.status(cellular: true, wifi: false, gatewayIP: nil, gatewayMs: nil)
        let ctx = VerdictInputs.context(status: s, vpnResult: nil, geoCountryCode: "CN", radioTechnology: "5G")
        #expect(ctx.isCellular && ctx.radioTechnology == "5G" && ctx.publicCountry == "CN")
        #expect(ctx.vpn == .unknown)                        // no detector result, no VPN flag → unknown, not "off"
        let wifi = VerdictInputs.context(status: Self.status(), vpnResult: nil, geoCountryCode: nil, radioTechnology: "LTE")
        #expect(wifi.radioTechnology == nil)                // radio tech is a cellular fact only
    }
}

struct TrendsOrderingTests {
    @Test func neutralNetworkChangedLine_neverDisplacesARealFinding() {
        func insight(_ sev: TrendAnalyzer.TrendInsight.Severity, _ metric: String) -> TrendAnalyzer.TrendInsight {
            TrendAnalyzer.TrendInsight(title: metric, description: "", severity: sev, metric: metric, changePercent: nil)
        }
        let ordered = TrendAnalyzer.ordered([insight(.neutral, TrendAnalyzer.networkChangedMetric), insight(.positive, "latency"), insight(.negative, "download")])
        #expect(ordered.map(\.metric) == ["download", "latency", TrendAnalyzer.networkChangedMetric])
        // The card shows prefix(2): the neutral line is the one left out.
        #expect(!ordered.prefix(2).contains { $0.metric == TrendAnalyzer.networkChangedMetric })
    }
}

// MARK: - Cellular segment key: country (Diagnosis v2 §G, Commit 5)

struct CellularCountryKeyTests {

    @Test func cellularKey_includesCountry_wifiKeyDoesNot() {
        #expect(NetworkSegment.key(connectionType: "Cellular", vpnActive: false, ssid: nil, subnet: "10.32.7", country: "cn") == "Cellular|direct|CN")
        #expect(NetworkSegment.key(connectionType: "Cellular", vpnActive: false, ssid: nil, subnet: nil, country: "US") == "Cellular|direct|US")
        #expect(NetworkSegment.key(connectionType: "Cellular", vpnActive: false, ssid: nil, subnet: nil, country: nil) == "Cellular|direct|-")   // legacy: coarse, never guessed
        #expect(NetworkSegment.key(connectionType: "WiFi", vpnActive: false, ssid: "HomeNet", subnet: "192.168.1", country: "US") == "WiFi|direct|HomeNet|192.168.1")
    }

    @Test func chinaCellularAndUSRoamingSIM_areNeverComparedAsATrend() {
        // 3 fast tests on China cellular, then 3 slow tests on a US SIM (newest).
        // Phase 4 alone keyed both as "Cellular|direct" → "Down 93%". Now: two segments, no delta.
        func speed(_ i: Int, down: Double, country: String) -> SpeedTestResult {
            var r = SpeedTestResult(downloadSpeed: down, uploadSpeed: down / 4, ping: 40, jitter: 3, packetLoss: 0, testDuration: 0,
                                    connectionType: "Cellular", vpnActive: false, publicCountry: country)
            r.timestamp = TrendsHonestyTests.base.addingTimeInterval(Double(i) * 600)
            return r
        }
        let h = [speed(0, down: 120, country: "CN"), speed(1, down: 118, country: "CN"), speed(2, down: 122, country: "CN"),
                 speed(3, down: 8, country: "US"), speed(4, down: 7, country: "US"), speed(5, down: 9, country: "US")]
        let insights = TrendAnalyzer.analyzeSpeedTrends(history: h)
        #expect(!insights.contains { $0.metric == "download" })
        #expect(h[5].segmentKey != h[0].segmentKey)
        // Same SIM abroad (home-routed roaming keeps CN): same backhaul path → still one segment.
        #expect(speed(9, down: 50, country: "cn").segmentKey == h[0].segmentKey)
    }

    @Test func legacyCellularRecords_withoutCountry_doNotMergeWithKeyedOnes() throws {
        let json = """
        [{"id":"66666666-6666-6666-6666-666666666666","timestamp":700000000,"downloadSpeed":90,"uploadSpeed":20,
          "testDuration":0,"connectionType":"Cellular","vpnActive":false,"quality":"Good"}]
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode([SpeedTestResult].self, from: json)[0]
        #expect(legacy.publicCountry == nil && legacy.segmentKey == "Cellular|direct|-")
        let keyed = SpeedTestResult(downloadSpeed: 90, uploadSpeed: 20, ping: nil, jitter: nil, packetLoss: nil, testDuration: 0,
                                    connectionType: "Cellular", vpnActive: false, publicCountry: "CN")
        #expect(keyed.segmentKey != legacy.segmentKey)
    }

    @Test func diagnosticEntry_carriesCountry_inCellularKey() {
        let e = DiagnosticHistoryEntry(timestamp: Date(), summary: "", issueCount: 0, primaryIssueCategory: "None", overallStatus: "green",
                                       connectionType: "Cellular", vpnActive: true, networkSSID: nil, localSubnet: nil, publicCountry: "US")
        #expect(e.segmentKey == "Cellular|vpn|US")
    }
}

// MARK: - Quick Check external target (Commit 6)

struct ExternalTargetTests {
    @Test func externalPingHost_isDomesticOnlyInChinaWithoutVPN() {
        #expect(NetworkMonitorService.externalPingHost(preferDomestic: true) == "www.baidu.com")
        #expect(NetworkMonitorService.externalPingHost(preferDomestic: false) == "apple.com")
    }

    @Test func failedExternalOrDNSTest_carriesNilLatency_neverZero() {
        // The Quick Check's failed tests must store nil so the Checks row shows
        // nothing rather than "0ms". Pin the model contract the view relies on.
        let failed = DiagnosticTest(name: "External Connectivity", result: .fail, latency: nil, details: "", timestamp: Date())
        #expect(failed.latency == nil)
        #expect(LatencyValidation.normalize(0) == 0)   // a stored 0 WOULD render as "0ms" — hence nil, not 0
    }
}

// MARK: - Commit 7: stability monitor self-interference, TLS unavailable, Deep Scan coverage

struct StabilityMonitorTests {
    typealias M = ConnectionStabilityMonitor

    @Test func samplesUnderAppLoad_recordNothing_andDropPendingCandidates() {
        // A speed test in progress: excellent → poor would be a "Degraded" event. Under load it is not evidence.
        let d = M.qualityTransition(recorded: .excellent, pending: .poor, pendingCount: 1, sample: .poor, underLoad: true)
        #expect(d == M.QualityDecision(record: nil, pending: nil, pendingCount: 0))
    }

    @Test func oneSampleBlip_isNotRecorded_persistenceRequired() {
        // Idle, excellent → poor seen once: pending only.
        let first = M.qualityTransition(recorded: .excellent, pending: nil, pendingCount: 0, sample: .poor, underLoad: false)
        #expect(first.record == nil && first.pending == .poor && first.pendingCount == 1)
        // Next sample back to excellent: candidate dropped, nothing recorded — the "green → red → green" flap is gone.
        let back = M.qualityTransition(recorded: .excellent, pending: .poor, pendingCount: 1, sample: .excellent, underLoad: false)
        #expect(back == M.QualityDecision(record: nil, pending: nil, pendingCount: 0))
    }

    @Test func persistentDegradation_isRecorded_onTheSecondSample() {
        let second = M.qualityTransition(recorded: .excellent, pending: .poor, pendingCount: 1, sample: .poor, underLoad: false)
        #expect(second.record == .degraded)
        let improved = M.qualityTransition(recorded: .poor, pending: .excellent, pendingCount: 1, sample: .excellent, underLoad: false)
        #expect(improved.record == .improved)
    }

    @Test func unknownIsNeitherBetterNorWorse() {
        #expect(!M.healthDegraded(from: .excellent, to: .unknown))   // losing a reading is not a degradation
        #expect(!M.healthImproved(from: .unknown, to: .excellent))
        let d = M.qualityTransition(recorded: .excellent, pending: nil, pendingCount: 0, sample: .unknown, underLoad: false)
        #expect(d.record == nil && d.pending == nil)
        #expect(M.healthDegraded(from: .excellent, to: .poor) && M.healthImproved(from: .poor, to: .excellent))
        #expect(!M.healthDegraded(from: .excellent, to: .fair))      // one step is not an event (unchanged rule)
    }

    @Test func highThroughputZeroLossRun_recordsNoInstability() {
        // The device run: 152 Mbps / 0 % loss speed test. The monitor's samples during the
        // test flip excellent → poor → excellent; all are under load, then the post-load
        // grace sample, then idle excellent. Simulate the sequence: nothing is recorded.
        var recorded: NetworkHealth? = .excellent
        var pending: NetworkHealth? = nil
        var count = 0
        var events: [M.QualityTransition] = []
        let sequence: [(NetworkHealth, Bool)] = [(.poor, true), (.poor, true), (.excellent, true), (.excellent, true /* grace */), (.excellent, false), (.excellent, false)]
        for (sample, load) in sequence {
            let d = M.qualityTransition(recorded: recorded, pending: pending, pendingCount: count, sample: sample, underLoad: load)
            pending = d.pending; count = d.pendingCount
            if let r = d.record { events.append(r); recorded = sample }
        }
        #expect(events.isEmpty)
    }
}

struct TLSAssessmentTests {
    typealias A = TLSAnalyzer
    static let cert = CertificateInfo(subject: "x", issuer: "DigiCert", serialNumber: "1", validFrom: nil, validTo: nil,
                                      publicKeyInfo: "", isSelfSigned: false, isRootCA: false, isTrusted: true)

    @Test func timedOutOrUnreachableHost_isUnavailable_notAGrade() {
        let a = A.classifyAssessment(chain: [], isTrusted: false, isProxyMITM: false, fetchErrorCode: -1001)
        #expect(a == .unavailable(.unreachable(code: -1001)))
        let b = A.classifyAssessment(chain: [], isTrusted: false, isProxyMITM: false, fetchErrorCode: -1004)
        #expect(b == .unavailable(.unreachable(code: -1004)))
        if case .unavailable(let r) = a { #expect(r.text.hasPrefix("Couldn't assess — host unreachable")) }
    }

    @Test func trustFailureWithoutProxyCA_isInterceptedOrBlocked_notCritical() {
        let a = A.classifyAssessment(chain: [Self.cert], isTrusted: false, isProxyMITM: false, fetchErrorCode: nil)
        #expect(a == .unavailable(.interceptedOrBlocked))
        if case .unavailable(let r) = a { #expect(r.text.contains("intercepted or blocked")) }
    }

    @Test func trustedChain_orKnownProxyCA_isACompletedAssessment() {
        #expect(A.classifyAssessment(chain: [Self.cert], isTrusted: true, isProxyMITM: false, fetchErrorCode: nil) == .completed)
        #expect(A.classifyAssessment(chain: [Self.cert], isTrusted: false, isProxyMITM: true, fetchErrorCode: nil) == .completed)
    }

    @Test func unavailableResult_hasNoRating_andIsNotSecure() {
        var r = TLSAnalysisResult(host: "chase.com", port: 443, tlsVersion: .unknown, certificateChain: [], issues: [],
                                  cipherSuite: nil, handshakeLatencyMs: nil, timestamp: Date())
        r.assessment = .unavailable(.interceptedOrBlocked)
        #expect(r.securityRating == nil)
        #expect(r.ratingText == "Couldn't assess")
        #expect(!r.isSecure)
    }
}

struct DeepScanCoverageTests {
    typealias S = AdvancedDiagnosticSummary

    @Test func noThreatCheckCompleted_isUnknown_neverSecure() {
        #expect(S.threatLevel(dnsBehavior: .allNormal, vpnLeaked: false, anyThreatCheckCompleted: false) == .unknown)
        #expect(S.threatLevel(dnsBehavior: .allNormal, vpnLeaked: false, anyThreatCheckCompleted: true) == .secure)
        #expect(S.threatLevel(dnsBehavior: .abnormalDNSBehavior, vpnLeaked: false, anyThreatCheckCompleted: true) == .high)
        #expect(S.threatLevel(dnsBehavior: .allNormal, vpnLeaked: true, anyThreatCheckCompleted: true) == .high)
    }

    @Test func timedOutDNSHijack_andNoVPN_yieldsUnknownWithCoverageLine() {
        let summary = S(timestamp: Date(), arpResult: nil, dnsHijackResults: [], vpnLeakResult: nil,
                        routingInterpretation: nil, performanceMetrics: nil, vpnRegionScores: [], wifiChannels: [], lanDevices: [],
                        networkDiagnosis: nil,
                        coverage: Coverage(records: [.failed(.dnsHijack, .timeout), .notApplicable(.vpnLeak, "no VPN in use"),
                                                     .ran(.traceroute, 3, unit: ""), .ran(.performance, 40, unit: "Mbps")]))
        #expect(summary.overallThreatLevel == .unknown)
        #expect(summary.summaryText == "Couldn't judge security — the threat checks didn't complete")
        #expect(summary.coverage?.line == "2 of 3 checks completed · 1 couldn't run — DNS hijack test timed out · not applicable — VPN leak test: no VPN in use")
    }

    @Test func completedDNSHijack_withNoVPN_isSecure_andSaysWhatCompleted() {
        let clean = DNSHijackResult(domain: "baidu.com", expectedIPs: ["110.242."], resolvedIPs: ["110.242.68.66"], hijacked: false, confidence: 1, region: .chinaNative)
        let summary = S(timestamp: Date(), arpResult: nil, dnsHijackResults: [clean], vpnLeakResult: nil,
                        routingInterpretation: nil, performanceMetrics: nil, vpnRegionScores: [], wifiChannels: [], lanDevices: [],
                        networkDiagnosis: nil,
                        coverage: Coverage(records: [.ran(.dnsHijack, 1, unit: ""), .notApplicable(.vpnLeak, "no VPN in use"),
                                                     .failed(.traceroute, .timeout), .ran(.performance, 40, unit: "Mbps")]))
        #expect(summary.overallThreatLevel == .secure)
        #expect(summary.summaryText == "No security threats found in the checks that completed")
    }

    @Test func legacySummary_withoutCoverage_keepsOldBehaviour() {
        let summary = S(timestamp: Date(), arpResult: nil, dnsHijackResults: [], vpnLeakResult: nil,
                        routingInterpretation: nil, performanceMetrics: nil, vpnRegionScores: [], wifiChannels: [], lanDevices: [], networkDiagnosis: nil)
        #expect(summary.coverage == nil && summary.overallThreatLevel == .secure)
    }
}
