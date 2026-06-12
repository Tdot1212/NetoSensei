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
