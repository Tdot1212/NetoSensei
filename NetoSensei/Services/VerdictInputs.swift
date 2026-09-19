//
//  VerdictInputs.swift
//  NetoSensei
//
//  Diagnosis v2 — check PRODUCERS (design §F 5a.2 / 5a.3).
//
//  Turns what the app already measures (NetworkStatus from the continuous
//  monitor, the Quick Check's DiagnosticResult, the most recent speed test)
//  into coverage-tagged CheckRecords plus a VerdictContext, and hands them to
//  VerdictComposer. Nothing here judges anything; it only reports what ran,
//  what failed, and what did not apply. Pure mapping functions are
//  unit-tested; the MainActor entry points only gather singletons.
//

import Foundation
import Network

enum VerdictInputs {

    /// Consecutive probe failures as tracked by MeasurementValidityTracker.
    struct FailureStreaks: Equatable {
        var gateway = 0
        var external = 0
        var dns = 0
    }

    /// A speed test is only evidence for the CURRENT network if it was run on
    /// the same segment and recently.
    static let speedTestFreshness: TimeInterval = 10 * 60

    // MARK: - Records from the continuous monitor

    /// - Parameter vpnOn: the SAME VPN judgement the context uses (detector +
    ///   monitor). Passing it keeps the vpnState check and `context.vpn` in
    ///   agreement; nil falls back to the monitor's flags alone.
    static func records(from status: NetworkStatus,
                        streaks: FailureStreaks,
                        recentSpeedTest: SpeedTestResult? = nil,
                        vpnOn vpnOverride: Bool? = nil,
                        now: Date = Date()) -> [CheckRecord] {
        var r: [CheckRecord] = []
        let cellularOnly = status.connectionType == .cellular && !status.wifi.isConnected
        let vpnOn = vpnOverride ?? (status.vpn.isActive || status.vpn.vpnState.isLikelyOn)

        // Router: never a failure when there is no router to test.
        if cellularOnly {
            r.append(.notApplicable(.gatewayLatency, "no router on cellular"))
        } else if let gw = status.router.displayableLatency {
            r.append(.ran(.gatewayLatency, gw, unit: "ms"))
            r.append(.ran(.gatewayReach, 1, unit: ""))
        } else if status.router.gatewayIP == nil {
            r.append(.notApplicable(.gatewayLatency, "router address couldn't be determined"))
        } else if vpnOn {
            r.append(.notApplicable(.gatewayLatency, "hidden by the VPN"))
        } else {
            let streak = max(1, streaks.gateway)
            r.append(.failed(.gatewayLatency, .timeout, streak: streak))
            r.append(.failed(.gatewayReach, .timeout, streak: streak))
        }

        // Internet delay: interception-aware (Phase 2.1). An intercepted probe
        // is a single, explained failure — pattern E3 owns it.
        if status.internet.latencyIntercepted {
            r.append(.failed(.externalLatency, .intercepted, streak: 1))
        } else if let ext = status.internet.displayableLatency {
            r.append(.ran(.externalLatency, ext, unit: "ms"))
        } else {
            r.append(.failed(.externalLatency, .timeout, streak: max(1, streaks.external)))
        }

        // Web reachability (the monitor's HTTPS test) and domestic reachability.
        if status.internet.isReachable {
            r.append(.ran(.httpReach, status.internet.httpTestSuccess ? 1 : 0, unit: ""))
            r.append(.ran(.domesticReach, 1, unit: ""))
        } else {
            r.append(.failed(.httpReach, .timeout, streak: max(1, streaks.external)))
            r.append(.ran(.domesticReach, 0, unit: ""))
        }

        // Address lookup.
        if let dns = status.dns.displayableLatency {
            r.append(.ran(.dnsResolve, 1, unit: ""))
            r.append(.ran(.dnsLatency, dns, unit: "ms"))
        } else if status.dns.lookupSuccess {
            r.append(.ran(.dnsResolve, 1, unit: ""))
            r.append(.notRun(.dnsLatency, "lookup worked but its timing was unavailable"))
        } else {
            r.append(.failed(.dnsResolve, .timeout, streak: max(1, streaks.dns)))
        }

        // VPN: a state, not a test.
        r.append(vpnOn ? .ran(.vpnState, 1, unit: "") : .notApplicable(.vpnState, "no VPN in use"))

        // Steadiness / dropped data: prefer a fresh same-network speed test
        // (end-to-end); otherwise the router probe's own samples (LAN only).
        let segment = NetworkSegment.key(connectionType: status.connectionType?.displayName ?? "Unknown",
                                         vpnActive: vpnOn,
                                         ssid: status.wifi.ssid,
                                         subnet: NetworkSegment.subnet(of: status.localIP))
        if let speed = recentSpeedTest,
           speed.segmentKey == segment,
           now.timeIntervalSince(speed.timestamp) < speedTestFreshness {
            if speed.downloadSpeed > 0 { r.append(.ran(.throughput, speed.downloadSpeed, unit: "Mbps", at: speed.timestamp)) }
            if let j = speed.jitter { r.append(.ran(.jitter, j, unit: "ms", at: speed.timestamp)) }
            if let loss = speed.packetLoss { r.append(.ran(.packetLoss, loss, unit: "%", at: speed.timestamp)) }
        } else if !cellularOnly, status.router.displayableLatency != nil {
            if let j = status.router.jitter { r.append(.ran(.jitter, j, unit: "ms")) }
            if let loss = status.router.packetLoss { r.append(.ran(.packetLoss, loss, unit: "%")) }
        }

        return r
    }

    // MARK: - Records from a Quick Check

    /// The Quick Check's six tests are REACHABILITY evidence layered over the
    /// monitor's interception-aware latencies. A test's own latency is used
    /// only when the monitor has none for that check.
    static func records(fromQuickCheck result: DiagnosticResult,
                        status: NetworkStatus,
                        streaks: FailureStreaks,
                        recentSpeedTest: SpeedTestResult? = nil,
                        vpnOn: Bool? = nil,
                        now: Date = Date()) -> [CheckRecord] {
        var base = records(from: status, streaks: streaks, recentSpeedTest: recentSpeedTest, vpnOn: vpnOn, now: now)
        func replace(_ id: CheckID, with rec: CheckRecord) {
            base.removeAll { $0.id == id }
            base.append(rec)
        }
        func test(_ name: String) -> DiagnosticTest? { result.testsPerformed.first { $0.name.contains(name) } }

        if let g = test("Gateway") {
            switch g.result {
            case .pass:
                if let l = g.latency, LatencyValidation.normalize(l) != nil, base.first(where: { $0.id == .gatewayLatency })?.status.didRun != true {
                    replace(.gatewayLatency, with: .ran(.gatewayLatency, l, unit: "ms"))
                }
                replace(.gatewayReach, with: .ran(.gatewayReach, 1, unit: ""))
            case .fail:
                replace(.gatewayReach, with: .failed(.gatewayReach, .timeout, streak: max(1, streaks.gateway + 1)))
                if base.first(where: { $0.id == .gatewayLatency })?.status.didRun != true {
                    replace(.gatewayLatency, with: .failed(.gatewayLatency, .timeout, streak: max(1, streaks.gateway + 1)))
                }
            case .warning:
                replace(.gatewayLatency, with: .notApplicable(.gatewayLatency, "router address was inferred, not confirmed"))
                base.removeAll { $0.id == .gatewayReach }
            case .notApplicable:
                replace(.gatewayLatency, with: .notApplicable(.gatewayLatency, plainReason(g.details, fallback: "no router on this network")))
                base.removeAll { $0.id == .gatewayReach }
            case .skipped:
                break
            }
        }

        if let e = test("External") {
            switch e.result {
            case .pass:
                if let l = e.latency, LatencyValidation.normalize(l) != nil, !status.internet.latencyIntercepted,
                   base.first(where: { $0.id == .externalLatency })?.status.didRun != true {
                    replace(.externalLatency, with: .ran(.externalLatency, l, unit: "ms"))
                }
            case .fail:
                replace(.externalLatency, with: .failed(.externalLatency, .timeout, streak: max(1, streaks.external + 1)))
            default: break
            }
        }

        if let d = test("DNS") {
            switch d.result {
            case .fail:
                replace(.dnsResolve, with: .failed(.dnsResolve, .timeout, streak: max(1, streaks.dns + 1)))
                base.removeAll { $0.id == .dnsLatency }
            case .pass, .warning:
                replace(.dnsResolve, with: .ran(.dnsResolve, 1, unit: ""))
                if let l = d.latency, LatencyValidation.normalize(l) != nil, base.first(where: { $0.id == .dnsLatency })?.status.didRun != true {
                    replace(.dnsLatency, with: .ran(.dnsLatency, l, unit: "ms"))
                }
            default: break
            }
        }

        if let h = test("HTTP") {
            switch h.result {
            case .pass: replace(.httpReach, with: .ran(.httpReach, 1, unit: ""))
            case .fail: replace(.httpReach, with: .failed(.httpReach, .blocked, streak: max(1, streaks.external + 1)))
            default: break
            }
        }

        return base
    }

    private static func plainReason(_ details: String, fallback: String) -> String {
        // "Not applicable — on cellular there is no local router to test" → "on cellular there is no local router to test"
        if let range = details.range(of: "— ") { return String(details[range.upperBound...]) }
        return fallback
    }

    // MARK: - Context

    static func context(status: NetworkStatus,
                        vpnResult: SmartVPNDetector.VPNDetectionResult?,
                        geoCountryCode: String?,
                        radioTechnology: String?) -> VerdictContext {
        let vpnOn = status.vpn.isActive || status.vpn.vpnState.isLikelyOn || (vpnResult?.vpnState.isLikelyOn ?? false)
        let vpn: VPNContext = {
            if let r = vpnResult {
                if r.vpnState.isLikelyOn { return .on(authoritative: r.isAuthoritative, exitCountry: r.publicCountry) }
                if r.vpnState == .unknown { return status.vpn.isActive ? .on(authoritative: false, exitCountry: nil) : .unknown }
                return status.vpn.isActive ? .on(authoritative: false, exitCountry: nil) : .off
            }
            return status.vpn.isActive ? .on(authoritative: false, exitCountry: nil) : .unknown
        }()
        let type = status.connectionType?.displayName ?? "Unknown"
        return VerdictContext(
            segmentKey: NetworkSegment.key(connectionType: type, vpnActive: vpnOn,
                                           ssid: status.wifi.ssid, subnet: NetworkSegment.subnet(of: status.localIP)),
            connectionType: type,
            vpn: vpn,
            latencyIntercepted: status.internet.latencyIntercepted,
            publicCountry: geoCountryCode ?? vpnResult?.publicCountry,
            expectedCountry: vpnResult?.expectedCountry,
            likelyInChina: vpnResult?.isLikelyInChina ?? false,
            radioTechnology: status.connectionType == .cellular ? radioTechnology : nil,
            isHotspot: status.isHotspot,
            publicIPVerified: vpnResult?.ipVerified ?? false
        )
    }

    // MARK: - MainActor entry points (gather singletons, then pure compose)

    @MainActor
    static func currentStreaks() -> FailureStreaks {
        let t = MeasurementValidityTracker.shared
        return FailureStreaks(gateway: t.gatewayConsecutiveFailures,
                              external: t.externalConsecutiveFailures,
                              dns: t.dnsConsecutiveFailures)
    }

    @MainActor
    static func currentContext(status: NetworkStatus) -> VerdictContext {
        let geo = GeoIPService.shared.currentGeoIP
        return context(status: status,
                       vpnResult: SmartVPNDetector.shared.detectionResult,
                       geoCountryCode: geo.publicIP.isEmpty ? nil : geo.countryCode,
                       radioTechnology: ConnectionComparator.shared.cellularInfo?.radioTechnology)
    }

    /// The verdict for the live dashboard.
    @MainActor
    static func currentVerdict(status: NetworkStatus) -> NetworkVerdict {
        let ctx = currentContext(status: status)
        let recs = records(from: status, streaks: currentStreaks(),
                           recentSpeedTest: HistoryManager.shared.speedTestHistory.first,
                           vpnOn: ctx.vpn.isOn)
        return VerdictComposer.compose(records: recs, context: ctx)
    }

    /// The verdict for a completed Quick Check.
    @MainActor
    static func verdict(forQuickCheck result: DiagnosticResult, status: NetworkStatus) -> NetworkVerdict {
        let ctx = currentContext(status: status)
        let recs = records(fromQuickCheck: result, status: status, streaks: currentStreaks(),
                           recentSpeedTest: HistoryManager.shared.speedTestHistory.first,
                           vpnOn: ctx.vpn.isOn)
        return VerdictComposer.compose(records: recs, context: ctx)
    }
}
