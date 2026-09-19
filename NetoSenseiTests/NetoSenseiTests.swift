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
                == "Cellular|vpn|-|-")
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
        #expect(records[0].segmentKey == "Cellular|vpn|-|-")
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
