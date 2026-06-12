//
//  LatencyInterceptionDetector.swift
//  NetoSensei
//
//  Detects when a local TUN-mode proxy/VPN (V2BOX, Shadowrocket, Clash, etc.)
//  has INTERCEPTED the external latency probe instead of measuring the real
//  network path.
//
//  WHY THIS EXISTS:
//  TUN-mode proxies — the norm for this app's mainland-China audience —
//  terminate outbound TCP handshakes LOCALLY. The on-device proxy stub ACKs
//  the SYN itself and establishes the real upstream connection asynchronously,
//  so a BSD connect()/handshake to an external host completes in ~1-4ms (the
//  cost of a localhost round-trip) regardless of the real network distance.
//  Displaying that number as "Latency" is fabricated data.
//
//  CALIBRATION DATA (measured 2026-06-12, Guangzhou, CMCC):
//    V2BOX ON:  TCP connect 223.5.5.5 = 1.5ms, 1.1.1.1 = 3.6ms   ← FAKE (local stub)
//    V2BOX OFF: TCP connect 223.5.5.5 = 14.8ms                   ← REAL
//    iPhone gateway handshake (device log) ~8.5ms                ← REAL (LAN, unproxied)
//    TUN proxies also drop ICMP entirely (100% ping loss both targets, VPN on)
//
//  The gateway handshake stays honest even with a proxy active: LAN / private-IP
//  traffic is not routed through the tunnel, so the gateway RTT is our physical
//  reference floor.
//
//  This detector is a PURE function so the speed-test phase (which sees the same
//  fake "Ping 999ms / 100% loss" alongside working throughput) can reuse it.
//

import Foundation

enum LatencyInterception {

    // MARK: - Calibrated thresholds

    /// Margin (ms) applied to the gateway comparison. An external handshake
    /// strictly faster than the gateway is physically impossible — every
    /// external packet must traverse the gateway. The margin absorbs gateway
    /// sample jitter so a real external RTT that merely sits close to the
    /// gateway RTT is not falsely flagged as intercepted.
    /// Calibration: V2BOX-ON external (1.5ms) sits ~7ms below the ~8.5ms
    /// gateway, far outside this margin; a real external reading is always
    /// >= the gateway, so 1ms of slack only protects honest near-gateway reads.
    static let gatewayMarginMs: Double = 1.0

    /// Absolute floor (ms) used only when no gateway reference is available
    /// (e.g. cellular, or the gateway exposes no open TCP port). A sub-2ms
    /// external handshake on WiFi/cellular is implausible — the WiFi radio hop
    /// alone is ~1-3ms. Deliberately conservative: well-peered anycast (AliDNS
    /// in some Chinese cities) can legitimately land at 3-5ms, so the floor
    /// must NOT flag that range. V2BOX-ON (1.5ms) falls below it; real reads
    /// (14.8ms domestic, 8.5ms+ gateway) sit well above.
    static let absoluteFloorMs: Double = 2.0

    // MARK: - Verdict

    struct Result {
        let intercepted: Bool
        /// Human-readable explanation for #if DEBUG logging / debug panels.
        let reason: String
    }

    /// Pure interception verdict, in order of physical authority.
    ///
    /// - Parameters:
    ///   - externalRTTms: measured external handshake RTT (ms). Caller passes
    ///     this only when the probe actually succeeded.
    ///   - gatewayRTTms: a FRESH gateway handshake RTT (ms), or nil when no
    ///     gateway is reachable/estimable. Must be an honest (unproxied) LAN
    ///     measurement.
    ///   - vpnActive: SmartVPNDetector's vpn-active state. CORROBORATION ONLY —
    ///     it is threaded through for logging and for the speed-test phase, but
    ///     it never flips the verdict on its own (a VPN can be active while the
    ///     probe path is honest, e.g. split tunnelling or IPSec without a local
    ///     TCP stub).
    static func evaluate(externalRTTms: Double,
                         gatewayRTTms: Double?,
                         vpnActive: Bool) -> Result {

        // AUTHORITY 1 — Gateway comparison (strongest; pure physics).
        // When a fresh gateway RTT exists it is the definitive reference:
        // external traffic cannot be faster than the local hop it must cross.
        if let gateway = gatewayRTTms {
            if externalRTTms < gateway - gatewayMarginMs {
                return Result(
                    intercepted: true,
                    reason: String(format:
                        "external %.1fms < gateway %.1fms − margin %.1fms (physically impossible; vpnActive=%@)",
                        externalRTTms, gateway, gatewayMarginMs, vpnActive ? "yes" : "no"))
            }
            // Gateway reference satisfied → honest path. Do NOT also apply the
            // absolute floor here: a genuinely sub-2ms external behind an
            // equally fast gateway (e.g. wired LAN) is real, and the gateway
            // comparison is the higher authority.
            return Result(
                intercepted: false,
                reason: String(format: "external %.1fms >= gateway %.1fms (plausible)",
                               externalRTTms, gateway))
        }

        // AUTHORITY 2 — Absolute floor (secondary; used when no gateway ref).
        if externalRTTms < absoluteFloorMs {
            return Result(
                intercepted: true,
                reason: String(format:
                    "external %.1fms < floor %.1fms, no gateway reference (implausible; vpnActive=%@)",
                    externalRTTms, absoluteFloorMs, vpnActive ? "yes" : "no"))
        }

        // AUTHORITY 3 — VPN-active corroboration is intentionally NOT sufficient
        // alone, so an honest reading with a VPN active stays MEASURED.
        return Result(
            intercepted: false,
            reason: String(format: "external %.1fms plausible (no gateway ref; vpnActive=%@)",
                           externalRTTms, vpnActive ? "yes" : "no"))
    }
}
