//
//  NetoSenseiTests.swift
//  NetoSenseiTests
//
//  Created by Tosh Yagishita on 15/12/2025.
//

import Testing
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
